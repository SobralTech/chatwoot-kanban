require 'rails_helper'

describe EmailHelper do
  describe '#render_email_html' do
    it 'returns an empty string for blank content' do
      expect(helper.render_email_html(nil)).to eq('')
      expect(helper.render_email_html('')).to eq('')
    end

    it 'renders a blockquote with the Gmail-style inline border/indent' do
      result = helper.render_email_html("Reply text\n\n> quoted text")
      expect(result).to include('<blockquote')
      expect(result).to include('border-left:1px solid #ccc')
      expect(result).to include('quoted text')
    end

    it 'renders regular markdown content as HTML' do
      result = helper.render_email_html('**bold** _italic_')
      expect(result).to include('<strong>bold</strong>')
      expect(result).to include('<em>italic</em>')
    end
  end

  describe '#normalize_email_with_plus_addressing' do
    context 'when email is passed' do
      it 'normalise if plus addressing is present' do
        expect(helper.normalize_email_with_plus_addressing('john+test@acme.inc')).to eq 'john@acme.inc'
      end

      it 'returns original if plus addressing is not present' do
        expect(helper.normalize_email_with_plus_addressing('john@acme.inc')).to eq 'john@acme.inc'
      end

      it 'returns downcased version of email' do
        expect(helper.normalize_email_with_plus_addressing('JoHn+AAsdfss@acme.inc')).to eq 'john@acme.inc'
      end
    end
  end
end
