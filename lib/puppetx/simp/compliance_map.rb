module PuppetX; end

# Create new environment-based module name
unless PuppetX.const_defined?("SIMP#{Puppet[:environment]}")
  PuppetX.const_set("SIMP#{Puppet[:environment]}", Module.new)
end

unless PuppetX.const_get("SIMP#{Puppet[:environment]}").const_defined?('ComplianceMap')
  PuppetX.const_get("SIMP#{Puppet[:environment]}").const_set(
    'ComplianceMap', Class.new(Object) do

      # Use load to make sure you catch the actual version of the file in the
      # correct environment.
      load File.expand_path(File.dirname(__FILE__) + '/compliance_map_ordered_hash.rb')

      # Just making this easier down the line
      def ordered_hash
        PuppetX.const_get("SIMP#{Puppet[:environment]}").const_get('CMOrderedHash').new
      end

      attr_reader :api_version
      attr_accessor :config

      def initialize(valid_profiles, config)
        @err_msg = "Error: malformed compliance map, see the function documentation for details."

        @config = config

        @api_version = '1.0.1'

        @valid_profiles ||= Array(valid_profiles)

        # Collect all cache misses to sticking onto the end of the profile reports
        @ref_misses = Hash.new()

        # Collect any resources that are in our mapping but have not been included
        @unmapped_resources = Hash.new()

        # Static Information
        @compliance_map = ordered_hash
        @compliance_map['version'] = @api_version

        @compliance_map.merge!(@config[:extra_data]) if @config[:extra_data]

        @compliance_map['compliance_profiles'] = ordered_hash
        @compliance_map['site_data'] = Hash.new()

        @valid_profiles.each do |profile|
          @compliance_map['compliance_profiles'][profile] ||= Hash.new()
        end
      end

      # Set up the main data structures
      #
      # @param compliance_profiles (Array) Compliance_profile strings that are
      #   valid for this ComplianceMap
      #
      # @param compliance_mapping (Hash) Data that represents the full compliance
      #   mapping
      #
      #   Example:
      #     {
      #       'compliance' => {
      #         '<profile>' => {
      #           '<fully_qualified_class_parameter>' => '<value'
      #         }
      #       }
      #     }
      #
      def setup_compliance_map(compliance_mapping)
        @compliance_map['site_data'] = @config[:site_data] if @config[:site_data]

        @valid_profiles.sort.each do |profile|
          @compliance_map['compliance_profiles'][profile] ||= ordered_hash
          @compliance_map['compliance_profiles'][profile]['summary'] ||= ordered_hash
          @compliance_map['compliance_profiles'][profile]['compliant'] ||= ordered_hash
          @compliance_map['compliance_profiles'][profile]['non_compliant'] ||= ordered_hash
          @compliance_map['compliance_profiles'][profile]['documented_missing_resources'] ||= Array.new()
          @compliance_map['compliance_profiles'][profile]['documented_missing_parameters'] ||= Array.new()
          @compliance_map['compliance_profiles'][profile]['custom_entries'] ||= ordered_hash

          @ref_misses[profile] ||= Array.new()
          @unmapped_resources[profile] ||= Array.new()
        end
      end

      def catalog_to_map(catalog)
        catalog_map = Hash.new()

        catalog_map['compliance_map::percent_sign'] = '%'
        catalog_map['compliance_map'] = {
          'version'                => @api_version,
          'generated_via_function' => Hash.new()
        }

        catalog.resources.each do |resource|
          # Ignore our own nonsense
          next if resource.name == 'Compliance_markup'

          if resource.name.is_a?(String) && (resource.name[0] =~ /[A-Z]/) && resource.parameters
            resource.parameters.each do |param_array|
              param = param_array.last

              param_name = %{#{resource.name}::#{param.name}}.downcase

              # We only want things with values
              next if param.value.nil?

              catalog_map['compliance_map']['generated_via_function'][param_name] = {
              'identifiers' => ['GENERATED'],
              'value'       => param.value
            }
            end
          end
        end

        return catalog_map.to_yaml
      end

      # Get all of the parts together for proper reporting and return the
      # result
      def format_map
        formatted_map = @compliance_map.dup
        report_types = @config[:report_types]

        @valid_profiles.each do |profile|

          # Create the summary report
          num_compliant     = formatted_map['compliance_profiles'][profile]['compliant'] ? formatted_map['compliance_profiles'][profile]['compliant'].keys.count : 0
          num_non_compliant = formatted_map['compliance_profiles'][profile]['non_compliant'] ? formatted_map['compliance_profiles'][profile]['non_compliant'].keys.count : 0

          total_checks = num_non_compliant + num_compliant
          percent_compliant = total_checks == 0 ? 0 : ((num_compliant.to_f/total_checks) * 100).round(0)

          formatted_map['compliance_profiles'][profile]['summary'] = {
            'compliant'                     => num_compliant,
            'non_compliant'                 => num_non_compliant,
            'percent_compliant'             => percent_compliant,
            'documented_missing_resources'  => @unmapped_resources[profile].count,
            'documented_missing_parameters' => @ref_misses[profile].count
          }

          unless report_types.include?('full')
            # Remove the built up content that does not apply to this system
            ['compliant', 'non_compliant', 'custom_entries'].each do |report_type|
              unless report_types.include?(report_type)
                formatted_map['compliance_profiles'][profile][report_type] = {}
              end
            end
          end

          if report_types.include?('full') || report_types.include?('unknown_resources')
            if @unmapped_resources[profile] && !@unmapped_resources[profile].empty?
              formatted_map['compliance_profiles'][profile]['documented_missing_resources'] = @unmapped_resources[profile].sort
            end
          end

          if report_types.include?('full') || report_types.include?('unknown_parameters')
            if @ref_misses && !@ref_misses[profile].empty?
              formatted_map['compliance_profiles'][profile]['documented_missing_parameters'] = @ref_misses[profile].sort
            end
          end

          # Strip out anything not relevant to the report
          formatted_map['compliance_profiles'][profile].delete_if{|k|
            val = formatted_map['compliance_profiles'][profile][k]

            val.nil? || val.empty?
          }
        end

        return formatted_map
      end

      def to_hash
        return format_map
      end

      def to_json
        require 'json'

        output = JSON.pretty_generate(format_map)

        return output
      end

      def to_yaml
        require 'yaml'

        output = format_map.to_yaml

        # Get rid of the ordered hash object information
        output.gsub!(%r( !ruby/.+CMOrderedHash), '')

        return output
      end

      # Add a custom entry to the Map
      #
      # @param resource_name (String) The name of the Puppet resource
      #
      # @param profile (String) The compliance profile under which this entry
      #   falls. The entry will not be added if this is not included in
      #   @valid_profiles
      #
      # @param identifiers (String) The compliance identifierss for the entry
      #
      # @param location (String) The 'file:line' formatted location of the
      #   function call
      #
      # @param opts (String) Custom Options
      #   * 'notes' (String) => Arbitrary notes about the entry
      #
      def add(resource_name, profile, identifiers, location, opts=ordered_hash)
        if @valid_profiles.include?(profile)
          data_hash = ordered_hash

          data_hash['location'] = location
          data_hash['identifiers'] = Array(identifiers)

          data_hash.merge!(opts)

          @compliance_map['compliance_profiles'][profile] ||= ordered_hash
          @compliance_map['compliance_profiles'][profile]['custom_entries'] ||= ordered_hash
          @compliance_map['compliance_profiles'][profile]['custom_entries'][resource_name] ||= []

          @compliance_map['compliance_profiles'][profile]['custom_entries'][resource_name] << data_hash
        end
      end

      def process_catalog(catalog, reference_map)
        setup_compliance_map(reference_map)

        target_resources = catalog.resources.select{|x| !x.parameters.empty?}

        @valid_profiles.each do |profile|
          next unless reference_map[profile]

          @unmapped_resources[profile] = reference_map[profile].keys.collect do |x|
            _tmp = x.split('::')
            _tmp.pop
            x = _tmp.join('::')
          end.sort.uniq

          # Gather up all of the possible keys in this profile
          #
          # Any items that remain are things that had a resource in Hiera but
          # were not found on the system
          @ref_misses[profile] = reference_map[profile].keys

          target_resources.each do |resource|
            human_name = resource.to_s
            resource_name = resource.name.downcase

            @unmapped_resources[profile].delete(resource_name)

            resource.parameters.keys.sort.each do |param|
              resource_ref = [resource_name, param].join('::')
              ref_entry = reference_map[profile][resource_ref]

              if ref_entry
                @ref_misses[profile].delete(resource_ref)
              else
                # If we didn't find an entry for this parameter, just skip it
                next
              end

              # Fail if the entry doesn't have the proper format
              required_metadata = ['identifiers','value']
              required_metadata.each do |md|
                raise "#{@err_msg} Failed on #{profile} profile, #{resource_ref} #{ref_entry}, metadata #{md}" if ref_entry[md].nil?
              end

              # Perform the actual matching
              ref_value = ref_entry['value']
              tgt_value = resource.parameters[param].value

              compliance_status = 'non_compliant'

              # Regular expression match
              if ref_value =~ /^re:(.+)/
                comparator = Regexp.new($1)

                if tgt_value =~ comparator
                  compliance_status = 'compliant'
                end
              # Default match
              elsif ref_value.to_s.strip == tgt_value.to_s.strip
                compliance_status = 'compliant'
              end

              report_data = ordered_hash
              report_data['identifiers'] = Array(reference_map[profile][resource_ref]['identifiers'])
              report_data['compliant_value'] = ref_value
              report_data['system_value'] = tgt_value

              # If we have other optional items, sort them, and stick them
              # into the report data
              (ref_entry.keys - required_metadata).sort.each do |extra_param|
                next if extra_param.nil?
                report_data[extra_param] = ref_entry[extra_param]
              end

              @compliance_map['compliance_profiles'][profile][compliance_status][human_name] ||= ordered_hash
              @compliance_map['compliance_profiles'][profile][compliance_status][human_name]['parameters'] ||= ordered_hash
              @compliance_map['compliance_profiles'][profile][compliance_status][human_name]['parameters'][resource_ref.split('::').last] = report_data
            end
          end

          # Strip anything out of @ref_misses that has an immediate parent in
          # @unmapped_resources

          @unmapped_resources[profile].each do |to_check|
            @ref_misses[profile].delete_if do |ref|
              ref_parts = ref.split('::')
              ref_parts.pop
              ref_parts.join('::') == to_check
            end
          end
        end
      end

      private

    end
  )
end
