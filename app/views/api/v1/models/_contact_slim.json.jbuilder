# The card lists only ever show a contact's identity, and the full contact partial
# resolves `availability_status` through Redis - one round trip per card rendered.
json.id resource.id
json.name resource.name
json.email resource.email
json.phone_number resource.phone_number
json.identifier resource.identifier
json.thumbnail resource.avatar_url
