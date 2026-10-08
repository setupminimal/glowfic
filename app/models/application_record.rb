# frozen_string_literal: true
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  # The record as it was at each of its audit versions, keyed by version. The audited gem's `revision(version)`
  # loads all the audits up to that version for each call; this loads them once for all the versions.
  def revisions_by_version
    versions = audits.pluck(:version)
    versions.zip(revisions).to_h
  end

  def audited_user_id
    user = Audited.store[:audited_user] # from as_user
    user ||= Audited.store[:current_user].call if Audited.store[:current_user].respond_to?(:call) # from controller method
    return nil if user.nil? && !Rails.env.test? # for debugging purposes this should fail loudly in tests
    user.id
  end
end
