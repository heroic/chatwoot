class AgentBotJob < ApplicationJob
  queue_as :bots

  def perform(agent_bot_id, message_id)
    return if ENV['RASA_URL'].blank?

    message = Message.find(message_id)

    bot_response = get_bot_response message

    return message.conversation.update(status: :open) if bot_response.nil? || bot_response == 'human_handoff'

    agent_bot = AgentBot.find(agent_bot_id)
    mb = Messages::MessageBuilder.new(agent_bot, message.conversation, {
                                        content: bot_response
                                      })
    mb.perform
  end

  private

  def get_bot_response(message)
    response = HTTParty.post(ENV['RASA_URL'], {
                                           body: {
                                             sender: message.conversation_id,
                                             message: message.content
                                           }.to_json
                                         })

    return unless response.code == 200

    body = JSON.parse(response.body)

    return body[0]['text'] if body[0].present? && body[0]['text'].present?
  end
end
