# Smart attribute for Slurm reservations
# Hides itself if no reservations are available for the user
# Hides the partition field if the user selects a reservation that specifies a partition
begin
  require_relative '../scripts/slurm_reservation'
rescue LoadError => e
  Rails.logger.error("Error loading slurm_reservation.rb: #{e}")
end
module SmartAttributes
  class AttributeFactory
    # Build this attribute object with defined options
    # @param opts [Hash] attribute's options
    # @return [Attributes::CSCPartition] the attribute object
    def self.build_csc_slurm_reservation(opts = {})
      Attributes::CSCReservation.new("csc_slurm_reservation", opts)
    end
  end

  module Attributes
    class CSCReservation < Attribute

      def initialize(id, opts={})
        opts[:cacheable] = opts.fetch(:cacheable, true)
        super(id, opts)
      end

      # Type of form widget used for this attribute
      # @return [String] widget type
      def widget
        # Hide this widget if the user has no reservations they can use
        if select_choices.length > 1
          "select"
        else
          "hidden_field"
        end
      end

      # Value should be empty if no reservation can be selected (allows caching of this field)
      def value
        if select_choices.length > 1 && opts[:value].to_s != "none"
          opts[:value].to_s
        else
          ""
        end
      end

      # Cache the reservations from Slurm
      def reservations
        @reservations ||= SlurmReservation.reservations
      end

      # Form label for this attribute
      # @param fmt [String, nil] formatting of form label
      # @return [String] form label
      def label(fmt: nil)
        (opts[:label] || "Reservation").to_s
      end

      def allowed_partition(partition)
        # Allowed partitions aren't specified
        if opts[:partitions].nil?
          true
        # Reservation doesn't specify partition
        elsif partition == "(null)"
          true
        else
          # Is partition for reservation allowed?
          opts[:partitions].include?(partition)
        end
      end

      def select_choice(reservation)
        # Hide the partition field in form if this reservation defines a partition
        extra_opts = nil
        if reservation.partition_name != "(null)"
          extra_opts = [{ "data-hide-csc-slurm-partition": true }]
        end
        inactive_text = if Time.now < reservation.start_time
            " (active from #{reservation.start_time.strftime("%Y-%m-%d %H:%M %Z")})"
          elsif Time.now > reservation.end_time
            " (expired)"
          elsif reservation.state == "INACTIVE"
            " (inactive)"
          else
            ""
          end
        [
          "#{reservation.name}#{inactive_text}",
          reservation.name,
          {
            "data-partition": reservation.partition_name,
            "disabled": ("true" unless inactive_text.empty?),
          },
          *extra_opts,
        ]
      end

      # Filter the available reservations based on the allowed partitions for this app
      def select_choices
        cache_expiry = nil #Time.now + 10.minutes
        result = Rails.cache.fetch("slurm_reservations", expires_in: 10.minutes) do
          # Fetch reservations again
          @reservations = SlurmReservation.reservations
          [["No reservation", "none", { "data-partition": "(null)" }]]
            .concat(reservations.map { |res|
              if res.start_time > Time.now && (cache_expiry.nil? || res.start_time < cache_expiry)
                cache_expiry = res.start_time
              end
              if res.end_time > Time.now && (cache_expiry.nil? || res.end_time < cache_expiry)
                cache_expiry = res.end_time
              end
              select_choice(res)
            })
        end
        if cache_expiry != nil
          Rails.cache.write("slurm_reservations", result, expires_in: [cache_expiry - Time.now + 1.second, 10.minutes].min)
        end
        result
      end

      # Submission hash describing how to submit this attribute
      # @param fmt [String, nil] formatting of hash
      # @return [Hash] submission hash
      def submit(fmt: nil)
        if value.blank?
          return {}
        end
        # Verify that the value here is an actual reservation
        reservation = reservations.find { |r| r.name == value }
        if reservation.nil?
          return {}
        else
          return { script: { reservation_id: value.strip } }
        end
      end
    end
  end
end
