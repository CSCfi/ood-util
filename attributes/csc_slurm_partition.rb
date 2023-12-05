begin
  require_relative '../scripts/slurm_project_partition'
rescue LoadError => e
  Rails.logger.error("Error loading slurm_project_partition.rb: #{e}")
end
module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCPartition] the attribute object
    def self.build_csc_slurm_partition(opts = {})
      Attributes::CSCPartition.new("csc_slurm_partition", opts)
    end
  end

  module Attributes
    class CSCPartition < Attribute

      def initialize(id, opts={})
        @@partitions ||= SlurmProjectPartition.partitions_with_data
        opts[:cacheable] = opts.fetch(:cacheable, true)
        opts[:help] ||= '<div id="partition_gpu_help" style="display: none;">The selected partition will reserve 1 <span id="partition_gpu_type">GPU</span> (<span id="partition_gpu_name"></span>).</div>'
        super(id, opts)
      end

      # Type of form widget used for this attribute
      # @return [String] widget type
      def widget
        "select"
      end

      # Filter the list of partitions based on the values provided in form.yml.erb
      def filter_partitions(partitions)
        if !opts[:ignore].nil?
          # Filter out values provided in the ignore attribute on csc_slurm_partition
          partitions.select {|partition, projects| !opts[:ignore].include?(partition) }
        elsif !opts[:select].nil?
          selected = opts[:select].map { |sel| sel.is_a?(Array) ? sel.first : sel }
          # Only include values provided in the select attribute on csc_slurm_partition
          partitions.select { |partition, projects| selected.include?(partition) }
        else
          partitions
        end
      end

      def get_partitions
        # Allow providing a fixed list of partitions without getting from Slurm
        if !opts[:partitions].nil?
          return opts[:partitions]
        end
        filter_partitions(@@partitions)
      end

      # Form label for this attribute
      # @param fmt [String, nil] formatting of form label
      # @return [String] form label
      def label(fmt: nil)
        (opts[:label] || "Partition").to_s
      end

      def select_choices
        filtered_partitions = get_partitions

        res_names = SlurmReservation.reservations.map(&:name)

        # Partition choices only availible in specific reservations
        res_partitions = SlurmReservation.reservations
          .map { |r|
            r.partitions
              .filter { |part| !filtered_partitions.keys.include?(part) } # Skip partitions available outside of reservations
              .map { |p| [p, [r.name]] }.to_h # Map to format {"<partition>": ["<reservation>"]}
          }.reduce({}) { |result, res_part| # Reduce to {"<partition>": ["<reservation1>", "<reservation2>"]}
            result.merge(res_part) { |part, old_res_list, new_res_list| old_res_list.concat(new_res_list) }
          }.map { |part, reservations|
            # Disable partition option for reservations without access
            data_opts = (res_names - reservations).map { |res| { "data-option-for-csc-slurm-reservation-#{res}".to_sym => false } }
            # Dynamic form attribute format
            [part, {"data-option-for-csc-slurm-reservation-none".to_sym => false}, *data_opts]
          }

        filtered_partitions.map do |partition, project_data|
          # Partition may have extra data included in form.yml, e.g. ["interactive", data-hide-somefield: true]
          partition_data = opts[:select]&.find { |sel| sel.is_a?(Array) && sel.first == partition }&.drop(1)
          [partition, *project_data, *partition_data]
        end.concat(
          res_partitions
        )
      end

      # Submission hash describing how to submit this attribute
      # @param fmt [String, nil] formatting of hash
      # @return [Hash] submission hash
      def submit(fmt: nil)
        { script: { queue_name: value.blank? ? nil : value.strip } }
      end
    end
  end
end
