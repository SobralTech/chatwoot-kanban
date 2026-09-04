require 'rails_helper'

describe Waha::Locking do
  let(:channel) { create(:channel_waha) }
  let(:chat_jid) { '5511888888888@c.us' }

  it 'serializes concurrent blocks for the same channel and chat' do
    order = Concurrent::Array.new
    barrier = Concurrent::CyclicBarrier.new(2)

    t1 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        barrier.wait
        described_class.with_chat_lock(channel, chat_jid) do
          order << :t1_enter
          sleep 0.05
          order << :t1_exit
        end
      end
    end

    t2 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        barrier.wait
        described_class.with_chat_lock(channel, chat_jid) do
          order << :t2_enter
          sleep 0.05
          order << :t2_exit
        end
      end
    end

    [t1, t2].each(&:join)

    expect(order.size).to eq(4)
    if order.first == :t1_enter
      expect(order.to_a).to eq(%i[t1_enter t1_exit t2_enter t2_exit])
    else
      expect(order.to_a).to eq(%i[t2_enter t2_exit t1_enter t1_exit])
    end
  end

  it 'allows different chats to execute independently without blocking' do
    other_chat = '5511999999999@c.us'
    order = Concurrent::Array.new
    barrier = Concurrent::CyclicBarrier.new(2)

    t1 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        barrier.wait
        described_class.with_chat_lock(channel, chat_jid) do
          order << :t1_enter
          sleep 0.05
          order << :t1_exit
        end
      end
    end

    t2 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        barrier.wait
        described_class.with_chat_lock(channel, other_chat) do
          order << :t2_enter
          sleep 0.05
          order << :t2_exit
        end
      end
    end

    [t1, t2].each(&:join)

    expect(order.size).to eq(4)
  end

  it 'skips locking and runs the block directly when channel or chat_jid is blank' do
    result = described_class.with_chat_lock(nil, chat_jid) { 42 }
    expect(result).to eq(42)

    result2 = described_class.with_chat_lock(channel, nil) { 99 }
    expect(result2).to eq(99)
  end
end
