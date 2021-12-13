# == Schema Information
#
# Table name: attachments
#
#  id               :integer          not null, primary key
#  coordinates_lat  :float            default(0.0)
#  coordinates_long :float            default(0.0)
#  extension        :string
#  external_url     :string
#  fallback_title   :string
#  file_type        :integer          default("image")
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :integer          not null
#  message_id       :integer          not null
#

class Attachment < ApplicationRecord
  include Rails.application.routes.url_helpers

  ACCEPTABLE_FILE_TYPES = %w[
    image/gif image/jpeg image/png image/bmp image/tiff image/webp
    audio/aac audio/midi audio/x-midi audio/mpeg audio/ogg audio/wav audio/webm audio/3gpp audio/3gpp2
    video/x-msvideo video/mp4 video/mpeg video/ogg video/webm video/3gpp video/3gpp2
    text/csv text/plain
    application/json application/pdf 
    application/zip application/x-7z-compressed application/vnd.rar application/x-tar
    application/msword application/vnd.ms-excel application/vnd.ms-powerpoint
    application/vnd.oasis.opendocument.text
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
  ].freeze

  belongs_to :account
  belongs_to :message
  has_one_attached :file
  validate :acceptable_file

  enum file_type: [:image, :audio, :video, :file, :location, :fallback]

  def push_event_data
    return unless file_type
    return base_data.merge(location_metadata) if file_type.to_sym == :location
    return base_data.merge(fallback_data) if file_type.to_sym == :fallback

    base_data.merge(file_metadata)
  end

  def file_url
    file.attached? ? url_for(file) : ''
  end

  def thumb_url
    if file.attached? && file.representable?
      url_for(file.representation(resize: '250x250'))
    else
      ''
    end
  end

  private

  def file_metadata
    {
      extension: extension,
      data_url: file_url,
      thumb_url: thumb_url
    }
  end

  def location_metadata
    {
      coordinates_lat: coordinates_lat,
      coordinates_long: coordinates_long,
      fallback_title: fallback_title,
      data_url: external_url
    }
  end

  def fallback_data
    {
      fallback_title: fallback_title,
      data_url: external_url
    }
  end

  def base_data
    {
      id: id,
      message_id: message_id,
      file_type: file_type,
      account_id: account_id
    }
  end

  def should_validate_file?
    return unless file.attached?
    # we are only limiting attachment types in case of website widget
    return unless message.inbox.channel_type == 'Channel::WebWidget'

    true
  end

  def acceptable_file
    return unless should_validate_file?

    errors.add(:file, 'is too big') if file.byte_size > 40.megabytes

    errors.add(:file, 'filetype not supported') unless ACCEPTABLE_FILE_TYPES.include?(file.content_type)
  end
end
