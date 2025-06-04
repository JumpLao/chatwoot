class Line::SendOnLineService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Line
  end

  def perform_reply
    response = send_using_reply_token
    response ||= channel.client.push_message(message.conversation.contact_inbox.source_id, build_payload)

    return if response.blank?

    parsed_json = JSON.parse(response.body)

    if response.code == '200'
      Messages::StatusUpdateService.new(message, 'delivered').perform
    else
      Messages::StatusUpdateService.new(message, 'failed', external_error(parsed_json)).perform
    end
  end

  def send_using_reply_token
    token = message.conversation.additional_attributes['line_reply_token']
    return if token.blank?

    response = channel.client.reply_message(token, build_payload)
    return unless response.code == '200'

    response
  end

  def build_payload
    if message.content && message.attachments.any?
      [text_message, *attachments]
    elsif message.content.nil? && message.attachments.any?
      attachments
    else
      text_message
    end
  end

  def attachments
    message.attachments.map do |attachment|
      # Support only image and video for now, https://developers.line.biz/en/reference/messaging-api/#image-message
      next unless attachment.file_type == 'image' || attachment.file_type == 'video'

      {
        type: attachment.file_type,
        originalContentUrl: attachment.download_url,
        previewImageUrl: attachment.download_url
      }
    end
  end

  # https://developers.line.biz/en/reference/messaging-api/#text-message
  def text_message
    {
      type: 'text',
      text: message.content
    }
  end

  # https://developers.line.biz/en/reference/messaging-api/#error-responses
  def external_error(error)
    # Message containing information about the error. See https://developers.line.biz/en/reference/messaging-api/#error-messages
    message = error['message']
    # An array of error details. If the array is empty, this property will not be included in the response.
    details = error['details']

    return message if details.blank?

    detail_messages = details.map { |detail| "#{detail['property']}: #{detail['message']}" }
    [message, detail_messages].join(', ')
  end
end
