require 'aws-sdk-ec2'
require 'aws-sdk-rds'
require 'aws-sdk-cloudwatch'
require 'aws-sdk-pricing'
require 'aws-sdk-elasticache'
require 'terminal-table'

class AWSResourceAuditor
  AWS_ACCESS_KEY_ID = ENV['AWS_ACCESS_KEY_ID']
  AWS_ACCESS_SECRET_KEY = ENV['AWS_ACCESS_SECRET_KEY']
  REGION = 'ap-south-1'

  def initialize
    configure_aws
    @ec2 = Aws::EC2::Client.new
    @rds = Aws::RDS::Client.new
    @cloudwatch = Aws::CloudWatch::Client.new
    @pricing = Aws::Pricing::Client.new
    @elasticache = Aws::ElastiCache::Client.new
  end

  def audit(services)
    services = ['1', '2', '3'] if services.empty?
    ec2_rows = services.include?('1') ? check_ec2_instances : []
    rds_rows = services.include?('2') ? check_rds_instances : []
    elasticache_rows = services.include?('3') ? check_elasticache_instances : []
    print_table(ec2_rows + rds_rows + elasticache_rows)
  end

  private

  def configure_aws
    if AWS_ACCESS_KEY_ID.empty? || AWS_ACCESS_SECRET_KEY.empty?
      raise 'AWS Access Key ID and Secret Access Key must be provided'
    end

    Aws.config.update(
      region: REGION,
      credentials: Aws::Credentials.new(AWS_ACCESS_KEY_ID, AWS_ACCESS_SECRET_KEY)
    )
  end

  def get_average_utilization(namespace, metric_name, dimension_name, resource_id)
    metrics = @cloudwatch.get_metric_data(
      start_time: Time.now - 3600 * 24 * 7,
      end_time: Time.now,
      metric_data_queries: [
        {
          id: 'utilization',
          metric_stat: {
            metric: {
              namespace: namespace,
              metric_name: metric_name,
              dimensions: [{ name: dimension_name, value: resource_id }]
            },
            period: 3600,
            stat: 'Average'
          }
        }
      ]
    )

    values = metrics.metric_data_results.first.values
    values.empty? ? nil : values.sum / values.size
  end

  def get_instance_pricing(service_code, instance_type)
    resp = @pricing.get_products(
      service_code: service_code,
      filters: [
        { type: 'TERM_MATCH', field: 'instanceType', value: instance_type },
        { type: 'TERM_MATCH', field: 'location', value: 'Asia Pacific (Mumbai)' }
      ],
      max_results: 1
    )

    price_dimensions = JSON.parse(resp.price_list.first)['terms']['OnDemand'].values.first['priceDimensions']
    price_dimensions.values.first['pricePerUnit']['USD'].to_f
  end

  def check_ec2_instances
    puts 'Checking for idle and underutilized EC2 instances...'
    instances = @ec2.describe_instances.reservations.flat_map(&:instances)
    total_hours = hours_till_now
    total_hours_in_month = hours_in_month

    instances.select { |i| i.state.name == 'running' }.map do |instance|
      avg_cpu_utilization = get_average_utilization('AWS/EC2', 'CPUUtilization', 'InstanceId', instance.instance_id)
      pricing_per_hour = get_instance_pricing('AmazonEC2', instance.instance_type)
      est_bill_for_month = total_hours_in_month * pricing_per_hour
      [
        instance.instance_id,
        instance.tags.find { |tag| tag.key == 'Name' }&.value || 'N/A',
        instance.instance_type,
        'EC2',
        instance.launch_time,
        avg_cpu_utilization || 'No data',
        'No data', # Memory utilization not available by default for EC2
        instance.instance_lifecycle || 'On-Demand',
        pricing_per_hour,
        total_hours * pricing_per_hour,
        est_bill_for_month
      ]
    end
  end

  def check_rds_instances
    puts 'Checking for idle and underutilized RDS instances...'
    instances = @rds.describe_db_instances.db_instances
    total_hours = hours_till_now
    total_hours_in_month = hours_in_month

    instances.map do |instance|
      avg_cpu_utilization = get_average_utilization('AWS/RDS', 'CPUUtilization', 'DBInstanceIdentifier', instance.db_instance_identifier)
      pricing_per_hour = get_instance_pricing('AmazonRDS', instance.db_instance_class)
      est_bill_for_month = total_hours_in_month * pricing_per_hour
      [
        instance.db_instance_identifier,
        instance.db_instance_identifier,
        instance.db_instance_class,
        'RDS',
        instance.instance_create_time,
        avg_cpu_utilization || 'No data',
        'No data', # Memory utilization not readily available for RDS
        'Reserved', # Placeholder for instance lifecycle
        pricing_per_hour,
        total_hours * pricing_per_hour,
        est_bill_for_month
      ]
    end
  end

  def check_elasticache_instances
    puts 'Checking for idle and underutilized ElastiCache instances...'
    instances = @elasticache.describe_cache_clusters.cache_clusters
    total_hours = hours_till_now
    total_hours_in_month = hours_in_month

    instances.map do |instance|
      avg_cpu_utilization = get_average_utilization('AWS/ElastiCache', 'CPUUtilization', 'CacheClusterId', instance.cache_cluster_id)
      pricing_per_hour = get_instance_pricing('AmazonElastiCache', instance.cache_node_type)
      est_bill_for_month = total_hours_in_month * pricing_per_hour
      [
        instance.cache_cluster_id,
        instance.cache_cluster_id,
        instance.cache_node_type,
        'ElastiCache',
        instance.cache_cluster_create_time,
        avg_cpu_utilization || 'No data',
        'No data', # Memory utilization not readily available for ElastiCache
        'Reserved', # Placeholder for instance lifecycle
        pricing_per_hour,
        total_hours * pricing_per_hour,
        est_bill_for_month
      ]
    end
  end

  def hours_till_now
    current_time = Time.now
    start_of_month = Time.new(current_time.year, current_time.month, 1, 0, 0, 0, current_time.utc_offset)
    ((current_time - start_of_month) / 3600).to_i
  end

  def hours_in_month
    current_time = Time.now
    start_of_month = Time.new(current_time.year, current_time.month, 1, 0, 0, 0, current_time.utc_offset)
    start_of_next_month = Time.new(current_time.year, current_time.month + 1, 1, 0, 0, 0, current_time.utc_offset)
    ((start_of_next_month - start_of_month) / 3600).to_i
  end

  def print_table(rows)
    table = Terminal::Table.new(
      title: 'AWS Resource Utilization',
      headings: ['ResourceID', 'ResourceName', 'ResourceFamily', 'ResourceType', 'ResourceCreationDate', 'AvgCPUUtilization', 'AvgMemoryUtilization', 'InstanceLifecycle', 'PricePerHour', 'EstBillMonthTillDate', 'EstBillForTheMonth'],
      rows: rows
    )
    puts table
  end
end

def get_user_input
  puts "Enter the numbers corresponding to the services you want to audit, separated by commas (e.g., 1,2,3):"
  puts "1 for EC2"
  puts "2 for RDS"
  puts "3 for ElastiCache"
  puts "Leave empty for all services"
  gets.chomp.split(',').map(&:strip)
end

services = get_user_input
AWSResourceAuditor.new.audit(services)