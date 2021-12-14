json.id resource.display_id
json.inbox_id resource.inbox_id
json.contact_last_seen_at resource.contact_last_seen_at.to_i
json.status resource.status
json.message resource.messages.last.content
json.contact resource.contact
