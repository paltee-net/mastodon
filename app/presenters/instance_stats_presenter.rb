# frozen_string_literal: true

class InstanceStatsPresenter < ActiveModelSerializers::Model
  attributes :delivery_stats

  def initialize(domain)
    super()
    @domain = domain
  end

  def delivery_histories
    @delivery_histories ||= DeliveryStatsTracker.new(@domain).hourly_delivery_histories(3.days.ago)
  end
end
