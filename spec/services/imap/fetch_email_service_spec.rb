require 'rails_helper'

RSpec.describe Imap::FetchEmailService do
  include ActionMailbox::TestHelper
  let(:logger) { instance_double(ActiveSupport::Logger, info: true, error: true) }
  let(:account) { create(:account) }
  let(:imap_email_channel) { create(:channel_email, :imap_email, account: account) }
  let(:imap) { instance_double(Net::IMAP) }
  let(:eml_content_with_message_id) { Rails.root.join('spec/fixtures/files/only_text.eml').read }
  let(:eml_content_without_message_id) { eml_content_with_message_id.sub(/^Message-ID:.*\n/, '') }
  let(:eml_content_with_other_message_id) { eml_content_with_message_id.sub(/^Message-ID:.*$/, 'Message-ID: <other-message-id@example.com>') }

  describe '#perform' do
    before do
      allow(Rails).to receive(:logger).and_return(logger)
      allow(Net::IMAP).to receive(:new).with(
        imap_email_channel.imap_address, port: imap_email_channel.imap_port, ssl: imap_email_channel.imap_enable_ssl
      ).and_return(imap)
      allow(imap).to receive(:authenticate).with(
        'plain', imap_email_channel.imap_login, imap_email_channel.imap_password
      )
      allow(imap).to receive(:select).with('INBOX')
    end

    context 'when using CRAM-MD5 authentication' do
      let(:cram_md5_channel) { create(:channel_email, :imap_email, account: account, imap_authentication: 'cram-md5') }

      before do
        allow(Net::IMAP).to receive(:new).with(
          cram_md5_channel.imap_address, port: cram_md5_channel.imap_port, ssl: cram_md5_channel.imap_enable_ssl
        ).and_return(imap)
        allow(imap).to receive(:authenticate).with(
          'CRAM-MD5', cram_md5_channel.imap_login, cram_md5_channel.imap_password
        )
        allow(imap).to receive(:select).with('INBOX')
      end

      it 'uses CRAM-MD5 authentication' do
        travel_to '26.10.2020 10:00'.to_datetime do
          allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([])
          allow(imap).to receive(:logout)

          described_class.new(channel: cram_md5_channel).perform

          expect(imap).to have_received(:authenticate).with(
            'CRAM-MD5', cram_md5_channel.imap_login, cram_md5_channel.imap_password
          )
        end
      end
    end

    context 'when using LOGIN authentication' do
      let(:login_channel) { create(:channel_email, :imap_email, account: account, imap_authentication: 'login') }

      before do
        allow(Net::IMAP).to receive(:new).with(
          login_channel.imap_address, port: login_channel.imap_port, ssl: login_channel.imap_enable_ssl
        ).and_return(imap)
        allow(imap).to receive(:login).with(
          login_channel.imap_login, login_channel.imap_password
        )
        allow(imap).to receive(:select).with('INBOX')
      end

      it 'uses LOGIN authentication' do
        travel_to '26.10.2020 10:00'.to_datetime do
          allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([])
          allow(imap).to receive(:logout)

          described_class.new(channel: login_channel).perform

          expect(imap).to have_received(:login).with(
            login_channel.imap_login, login_channel.imap_password
          )
        end
      end
    end

    context 'when new emails are available in the mailbox' do
      it 'fetches the emails and returns the emails that are not present in the db' do
        travel_to '26.10.2020 10:00'.to_datetime do
          email_object = create_inbound_email_from_fixture('only_text.eml')
          email_header = Net::IMAP::FetchData.new(1, 'BODY[HEADER]' => eml_content_with_message_id)
          imap_fetch_mail = Net::IMAP::FetchData.new(1, 'RFC822' => eml_content_with_message_id)

          allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([1])
          allow(imap).to receive(:fetch).with([1], 'BODY.PEEK[HEADER]').and_return([email_header])
          allow(imap).to receive(:fetch).with(1, 'RFC822').and_return([imap_fetch_mail])
          allow(imap).to receive(:logout)

          result = described_class.new(channel: imap_email_channel).perform

          expect(result.length).to eq 1
          expect(result[0].message_id).to eq email_object.message_id
          expect(imap).to have_received(:search).with(%w[SINCE 25-Oct-2020])
          expect(imap).to have_received(:fetch).with([1], 'BODY.PEEK[HEADER]')
          expect(imap).to have_received(:fetch).with(1, 'RFC822')
          expect(logger).to have_received(:info).with("[IMAP::FETCH_EMAIL_SERVICE] Fetching mails from #{imap_email_channel.email}, found 1.")
          expect(imap).to have_received(:logout)
        end
      end

      it 'fetches the emails and returns the mail objects that are not present in the db' do
        travel_to '26.10.2020 10:00'.to_datetime do
          email_object = create_inbound_email_from_fixture('only_text.eml')
          create(:message, source_id: email_object.message_id, account: account, inbox: imap_email_channel.inbox)

          email_header = Net::IMAP::FetchData.new(1, 'BODY[HEADER]' => eml_content_with_message_id)

          allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([1])
          allow(imap).to receive(:fetch).with([1], 'BODY.PEEK[HEADER]').and_return([email_header])
          allow(imap).to receive(:logout)

          result = described_class.new(channel: imap_email_channel).perform

          expect(result.length).to eq 0
          expect(imap).to have_received(:search).with(%w[SINCE 25-Oct-2020])
          expect(imap).to have_received(:fetch).with([1], 'BODY.PEEK[HEADER]')
          expect(imap).not_to have_received(:fetch).with(1, 'RFC822')
        end
      end

      it 'does not count emails without message ids toward the sync limit' do
        travel_to '26.10.2020 10:00'.to_datetime do
          email_object = create_inbound_email_from_fixture('only_text.eml')
          max_messages_per_sync = Imap::BaseFetchEmailService::MAX_MESSAGES_PER_SYNC
          empty_message_id_seq_nums = (1..max_messages_per_sync).to_a
          valid_message_seq_num = max_messages_per_sync + 1
          empty_message_id_headers = empty_message_id_seq_nums.map do |seq_num|
            Net::IMAP::FetchData.new(seq_num, 'BODY[HEADER]' => eml_content_without_message_id)
          end
          valid_email_header = Net::IMAP::FetchData.new(valid_message_seq_num, 'BODY[HEADER]' => eml_content_with_message_id)
          imap_fetch_mail = Net::IMAP::FetchData.new(valid_message_seq_num, 'RFC822' => eml_content_with_message_id)

          allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return(empty_message_id_seq_nums + [valid_message_seq_num])
          allow(imap).to receive(:fetch).with(empty_message_id_seq_nums, 'BODY.PEEK[HEADER]').and_return(empty_message_id_headers)
          allow(imap).to receive(:fetch).with([valid_message_seq_num], 'BODY.PEEK[HEADER]').and_return([valid_email_header])
          allow(imap).to receive(:fetch).with(valid_message_seq_num, 'RFC822').and_return([imap_fetch_mail])
          allow(imap).to receive(:logout)

          result = described_class.new(channel: imap_email_channel).perform

          expect(result.length).to eq 1
          expect(result[0].message_id).to eq email_object.message_id
          expect(imap).to have_received(:fetch).with(empty_message_id_seq_nums, 'BODY.PEEK[HEADER]')
          expect(imap).to have_received(:fetch).with([valid_message_seq_num], 'BODY.PEEK[HEADER]')
          expect(imap).to have_received(:fetch).with(valid_message_seq_num, 'RFC822')
        end
      end
    end

    context 'when imap_folders is configured' do
      let(:custom_folder_email) { create_inbound_email_from_fixture('only_text.eml') }
      let(:custom_folder_header) { Net::IMAP::FetchData.new(1, 'BODY[HEADER]' => eml_content_with_message_id) }
      let(:custom_folder_fetch_mail) { Net::IMAP::FetchData.new(1, 'RFC822' => eml_content_with_message_id) }

      before do
        allow(imap).to receive(:logout)
      end

      it 'falls back to INBOX when imap_folders is blank' do
        travel_to '26.10.2020 10:00'.to_datetime do
          allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([])

          described_class.new(channel: imap_email_channel).perform

          expect(imap).to have_received(:select).with('INBOX').once
        end
      end

      it 'selects only the configured single folder' do
        imap_email_channel.update!(imap_folders: ['Chatwoot'])

        travel_to '26.10.2020 10:00'.to_datetime do
          allow(imap).to receive(:select).with('Chatwoot')
          allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([])

          described_class.new(channel: imap_email_channel).perform

          expect(imap).to have_received(:select).with('Chatwoot')
          expect(imap).not_to have_received(:select).with('INBOX')
        end
      end

      it 'selects multiple configured folders and concatenates their results' do
        imap_email_channel.update!(imap_folders: %w[INBOX Chatwoot])
        other_folder_header = Net::IMAP::FetchData.new(1, 'BODY[HEADER]' => eml_content_with_other_message_id)
        other_folder_fetch_mail = Net::IMAP::FetchData.new(1, 'RFC822' => eml_content_with_other_message_id)

        travel_to '26.10.2020 10:00'.to_datetime do
          allow(imap).to receive(:select).with('INBOX')
          allow(imap).to receive(:select).with('Chatwoot')
          allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([1])
          # Sequential values: first call (INBOX) returns the first message, second call (Chatwoot) returns the second.
          allow(imap).to receive(:fetch).with([1], 'BODY.PEEK[HEADER]').and_return([custom_folder_header], [other_folder_header])
          allow(imap).to receive(:fetch).with(1, 'RFC822').and_return([custom_folder_fetch_mail], [other_folder_fetch_mail])

          result = described_class.new(channel: imap_email_channel).perform

          expect(imap).to have_received(:select).with('INBOX')
          expect(imap).to have_received(:select).with('Chatwoot')
          expect(result.length).to eq 2
          expect(result.map(&:message_id)).to contain_exactly(custom_folder_email.message_id, 'other-message-id@example.com')
        end
      end

      it 'does not return the same message twice when it exists in more than one folder' do
        imap_email_channel.update!(imap_folders: %w[INBOX Chatwoot])

        travel_to '26.10.2020 10:00'.to_datetime do
          allow(imap).to receive(:select).with('INBOX')
          allow(imap).to receive(:select).with('Chatwoot')
          allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([1])
          allow(imap).to receive(:fetch).with([1], 'BODY.PEEK[HEADER]').and_return([custom_folder_header])
          allow(imap).to receive(:fetch).with(1, 'RFC822').and_return([custom_folder_fetch_mail])

          result = described_class.new(channel: imap_email_channel).perform

          expect(result.length).to eq 1
          expect(result[0].message_id).to eq custom_folder_email.message_id
        end
      end

      it 'logs and skips a folder that fails to select, while still processing the remaining folders' do
        imap_email_channel.update!(imap_folders: %w[DoesNotExist Chatwoot])
        no_response_error = Net::IMAP::NoResponseError.new(
          Struct.new(:data).new(Struct.new(:text).new('no such mailbox'))
        )

        travel_to '26.10.2020 10:00'.to_datetime do
          allow(imap).to receive(:select).with('DoesNotExist').and_raise(no_response_error)
          allow(imap).to receive(:select).with('Chatwoot')
          allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([1])
          allow(imap).to receive(:fetch).with([1], 'BODY.PEEK[HEADER]').and_return([custom_folder_header])
          allow(imap).to receive(:fetch).with(1, 'RFC822').and_return([custom_folder_fetch_mail])

          result = described_class.new(channel: imap_email_channel).perform

          expect(result.length).to eq 1
          expect(result[0].message_id).to eq custom_folder_email.message_id
          expect(logger).to have_received(:error).with(
            "[IMAP::FETCH_EMAIL_SERVICE] Failed to select folder 'DoesNotExist' for #{imap_email_channel.email}: no such mailbox"
          )
        end
      end
    end
  end
end
