class AutoTagJob < ApplicationJob
  queue_as :medium_priority

  def perform(family, transaction_ids: [])
    family.auto_tag_transactions(transaction_ids)
  end
end
