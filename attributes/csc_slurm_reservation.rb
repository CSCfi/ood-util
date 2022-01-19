# Smart attribute for Slurm reservations
# Hides itself if no reservations are available for the user
# Hides the partition field if the user selects a reservation that specifies a partition
begin
  require_relative '../scripts/slurm_reservation'
rescue LoadError
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
        super(id, opts)
      end

      # Type of form widget used for this attribute
      # @return [String] widget type
      def widget
        # Hide this widget if the user has no reservations they can use
        if reservations.length > 0
          "select"
        else
          "hidden_field"
        end
      end

      # Value should be empty if no reservation can be selected (allows caching of this field)
      def value
        if reservations.length > 0
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

      def select_choice(reservation)
        # Hide the partition field in form if this reservation defines a partition
        extra_opts = nil
        if !reservation.partition_name.empty?
          extra_opts = {"data-hide-csc-slurm-partitions": true}
        end
        [reservation.name, reservation.name, extra_opts].compact
      end

      def select_choices
        # Always have an option for no reservation
        @select_choices ||= [["", ""]].concat(reservations.map { |res| select_choice(res) } )
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
        end
        # Use reservation partition if defined, overrides the partition field value
        if reservation.partition == "(nil)"
          return { script: { reservation_id: value.strip } }
        else
          return { script: { queue_name: reservation.partition, reservation_id: value.strip } }
        end
      end
    end
  end
end
