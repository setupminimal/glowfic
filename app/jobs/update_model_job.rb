# frozen_string_literal: true
# used to do bulk updates of a single model (e.g. Post)
# when there are potentially too many objects to be updated,
# slow callbacks, or similar complications such that performing
# the updates synchronously in the API is undesirable.

class UpdateModelJob < ApplicationJob
  queue_as :low

  def perform(klass, where_vals, new_attrs, user_id=0)
    # hopefully only necessary for the migration when old jobs won't yet have ID sent
    if user_id == 0
      UpdateModelJob.notify_exception(ArgumentError, klass, where_vals, new_attrs)
      update_records(klass, where_vals, new_attrs)
      return
    end

    # keeping this update for now even if no user is found because we don't yet know if we missed anything
    unless (user = User.find_by(id: user_id))
      UpdateModelJob.notify_exception(ActiveRecord::RecordNotFound, klass, where_vals, new_attrs, user_id)
      update_records(klass, where_vals, new_attrs)
      return
    end

    Audited.audit_class.as_user(user) do
      update_records(klass, where_vals, new_attrs)
    end
  end

  # What the callbacks and validations of each kind of model look up, loaded with the models instead of for each
  PRELOADS = {
    'Post'      => [:board, :user],
    'Reply'     => [{ post: :board }, :user],
    'Character' => [:user],
  }.freeze

  def update_records(klass, where_vals, new_attrs)
    model_class = klass.constantize
    model_class.where(where_vals).preload(*PRELOADS.fetch(klass, [])).find_each do |model|
      model.update!(new_attrs)
    end
  end
end
