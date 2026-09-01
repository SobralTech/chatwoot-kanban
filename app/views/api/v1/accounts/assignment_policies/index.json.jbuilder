json.array! @assignment_policies do |assignment_policy|
  json.partial! 'assignment_policy', assignment_policy: assignment_policy,
                                     assigned_inbox_count: @assigned_inbox_counts.fetch(assignment_policy.id, 0)
end
