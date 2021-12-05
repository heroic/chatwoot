# == Schema Information
#
# Table name: contacts
#
#  id                    :integer          not null, primary key
#  additional_attributes :jsonb
#  custom_attributes     :jsonb
#  email                 :string
#  identifier            :string
#  last_activity_at      :datetime
#  name                  :string
#  phone_number          :string
#  pubsub_token          :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :integer          not null
#
# Indexes
#
#  index_contacts_on_account_id                   (account_id)
#  index_contacts_on_phone_number_and_account_id  (phone_number,account_id)
#  index_contacts_on_pubsub_token                 (pubsub_token) UNIQUE
#  uniq_email_per_account_contact                 (email,account_id) UNIQUE
#  uniq_identifier_per_account_contact            (identifier,account_id) UNIQUE
#

class Contact < ApplicationRecord
  # TODO: remove the pubsub_token attribute from this model in future.
  include Avatarable
  include AvailabilityStatusable
  include Labelable

  validates :account_id, presence: true
  validates :email, allow_blank: true, uniqueness: { scope: [:account_id], case_sensitive: false }
  validates :identifier, allow_blank: true, uniqueness: { scope: [:account_id] }
  validates :phone_number,
            allow_blank: true, uniqueness: { scope: [:account_id] },
            format: { with: /\+[1-9]\d{1,14}\z/, message: 'should be in e164 format' }

  belongs_to :account
  has_many :conversations, dependent: :destroy
  has_many :contact_inboxes, dependent: :destroy
  has_many :csat_survey_responses, dependent: :destroy
  has_many :inboxes, through: :contact_inboxes
  has_many :messages, as: :sender, dependent: :destroy
  has_many :notes, dependent: :destroy

  before_validation :prepare_email_attribute
  after_create_commit :dispatch_create_event, :ip_lookup
  after_update_commit :dispatch_update_event
  after_destroy_commit :dispatch_destroy_event

  scope :order_on_last_activity_at, lambda { |direction|
    order(
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order("\"contacts\".\"last_activity_at\" #{direction}
          NULLS LAST")
      )
    )
  }
  scope :order_on_company_name, lambda { |direction|
    order(
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order(
          "\"contacts\".\"additional_attributes\"->>'company_name' #{direction}
          NULLS LAST"
        )
      )
    )
  }
  scope :order_on_city, lambda { |direction|
    order(
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order(
          "\"contacts\".\"additional_attributes\"->>'city' #{direction}
          NULLS LAST"
        )
      )
    )
  }
  scope :order_on_country_name, lambda { |direction|
    order(
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order(
          "\"contacts\".\"additional_attributes\"->>'country' #{direction}
          NULLS LAST"
        )
      )
    )
  }

  scope :order_on_name, lambda { |direction|
    order(
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order(
          "CASE
           WHEN \"contacts\".\"name\" ~~* '^+\d*' THEN 'z'
           WHEN \"contacts\".\"name\"  ~~*  '^\b*' THEN 'z'
           ELSE LOWER(\"contacts\".\"name\")
           END #{direction}"
        )
      )
    )
  }

  def get_source_id(inbox_id)
    contact_inboxes.find_by!(inbox_id: inbox_id).source_id
  end

  def push_event_data
    {
      additional_attributes: additional_attributes,
      custom_attributes: custom_attributes,
      email: email,
      id: id,
      identifier: identifier,
      name: name,
      phone_number: phone_number,
      pubsub_token: pubsub_token,
      thumbnail: avatar_url,
      type: 'contact'
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      avatar: avatar_url,
      type: 'contact',
      account: account.webhook_data
    }
  end

  def self.resolved_contacts
    where.not(email: [nil, '']).or(
      Current.account.contacts.where.not(phone_number: [nil, ''])
    ).or(Current.account.contacts.where.not(identifier: [nil, '']))
  end

  def fetch_contact_external_details
    return unless custom_attributes.nil? || custom_attributes[:external_id].nil?

    user_id = galaxycard_user_id
    # here we use the contact's email/phone to find the customer in thor
    # we save the user's thor id, and missing detail such as phone/email. this makes it easier to link with other details of the user
    unless user_id.nil?
      self.custom_attributes ||= {}
      self.custom_attributes[:external_id] = user_id
      assign_contact_details user_id
    end
    save
  end

  private

  def galaxycard_user_id_from_contact(body)
    response = HTTParty.post("http://thor.#{ENV['NAMESPACE']}/v1/users/findBy", body: body)
    return unless response.code == 200

    user = JSON.parse(response.body)[0]
    user['id'] unless user.nil?
  end

  def galaxycard_user_id
    user_id = nil
    user_id = galaxycard_user_id_from_contact(phone: phone_number.last(10)) if phone_number.present?
    user_id = galaxycard_user_id_from_contact(email: email) if user_id.nil? && email.present?
    user_id
  end

  def galaxycard_user_details(id)
    response = HTTParty.get("http://thor.#{ENV['NAMESPACE']}/v1/users/#{id}")
    return JSON.parse(response.body) if response.code == 200
  end

  def assign_contact_details(id)
    return unless phone_number.nil? || email.nil?

    user = galaxycard_user_details id
    return if user.nil?

    self.phone_number ||= user['phone'].to_s.length == 10 ? "+91#{user['phone']}" : user['phone']
    self.email ||= user['email']
  end

  def ip_lookup
    return unless account.feature_enabled?('ip_lookup')

    ContactIpLookupJob.perform_later(self)
  end

  def prepare_email_attribute
    # So that the db unique constraint won't throw error when email is ''
    self.email = nil if email.blank?
    email.downcase! if email.present?
  end

  def dispatch_create_event
    Rails.configuration.dispatcher.dispatch(CONTACT_CREATED, Time.zone.now, contact: self)
  end

  def dispatch_update_event
    Rails.configuration.dispatcher.dispatch(CONTACT_UPDATED, Time.zone.now, contact: self)
  end

  def dispatch_destroy_event
    Rails.configuration.dispatcher.dispatch(CONTACT_DELETED, Time.zone.now, contact: self)
  end
end
