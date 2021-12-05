class FetchContactDetailsJob < ApplicationJob
  queue_as :default

  def perform(contact_id)
    Contact.find(contact_id).fetch_contact_external_details
  end
end
