class EligibleDeaAdvertisementFilter
  def initialize(dea_advertisements, app_id)
    @filtered_advertisements = dea_advertisements.dup
    @app_id = app_id

    @instance_counts_by_zones = Hash.new(0)
    dea_advertisements.each { |ad| @instance_counts_by_zones[ad.zone] += ad.num_instances_of(@app_id) }
  end

  def only_with_disk(minimum_disk)
    @filtered_advertisements.select! { |ad| ad.has_sufficient_disk?(minimum_disk) }
    self
  end

  def only_meets_needs(mem, stack)
    @filtered_advertisements.select! { |ad| ad.meets_needs?(mem, stack) }
    self
  end

  def only_fewest_instances_of_app
    fewest_instances_of_app = @filtered_advertisements.map { |ad| ad.num_instances_of(@app_id) }.min
    @filtered_advertisements.select! { |ad| ad.num_instances_of(@app_id) == fewest_instances_of_app }
    self
  end

  def upper_half_by_memory
    unless @filtered_advertisements.empty?
      @filtered_advertisements.sort_by! { |ad| ad.available_memory }
      min_eligible_memory = @filtered_advertisements[@filtered_advertisements.size/2].available_memory
      @filtered_advertisements.select! { |ad| ad.available_memory >= min_eligible_memory }
    end

    self
  end

  def sample
    @filtered_advertisements.sample
  end

  def only_in_zone_with_fewest_instances
    minimum_instance_count = @filtered_advertisements.map { |ad| @instance_counts_by_zones[ad.zone] }.min
    @filtered_advertisements.select! { |ad| @instance_counts_by_zones[ad.zone] == minimum_instance_count }
    self
  end

  def only_in_featured_dea(dea_feature_options, app_org, app_space)
    if !dea_feature_options.blank? && dea_feature_options.has_key?(app_org) && dea_feature_options[app_org].has_key?(app_space)
       @filtered_advertisements.select! {|ad| is_featured_dea?(ad.dea_features, dea_feature_options[app_org][app_space])}
    end
    self
  end

  private

  # NOTE: You can only filter dea by features you specified in dea's yaml, aka, if you do not give value to 'foo' feature, cc will
  # never know that dea is 'foo' or not, even you provided 'foo' condition on cc's side.
  def is_featured_dea?(real_world_from_dea, expected_from_cc)
    matched = true
    expected_from_cc.each { |key, value|
      if real_world_from_dea[key] != value
        matched = false
        break
      end
    }
    matched
  end

end
