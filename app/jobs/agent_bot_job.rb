class AgentBotJob < ApplicationJob
  queue_as :bots

  def perform(agent_bot_id, message_id)
    return unless ENV['RASA_URL'].present?

    message = Message.find(message_id)
    response = Webhooks::Trigger.execute(ENV['RASA_URL'], {
      sender: message.conversation_id,
      message: message.content,
      name: message.sender.name,
      email: message.sender.email,
      phone: message.sender.phone,
      user_id: message.sender.custom_attributes.present? ? message.sender.custom_attributes['external_id'] : nil,
    })

    message.conversation.status = :open

    return message.conversation.save unless response.code == 200

    body = JSON.parse(response.body)

    return message.conversation.save unless body[0].present? && body[0]['text'].present?

    return message.conversation.save if body[0]['text'] == 'human_handoff'

    agent_bot = AgentBot.find(agent_bot_id)
    mb = Messages::MessageBuilder.new(agent_bot, message.conversation, {
      content: body[0]['text'],
    })
    mb.perform

    message.conversation.status = :pending
    message.conversation.save
  end
end
