class Hiera
  module Backend
    class Compliance_map_backend
      def initialize
        Hiera.debug('Hiera Compliance Map backend starting')
      end

      def lookup(key, scope, order_override, resolution_type, context)
        Hiera.debug("Looking up #{key} in Compliance Map backend")

        answer = nil

        if Object.const_defined?('Puppet') && scope.respond_to?(:real)
          compliance_profile_to_enforce = lookup_global_silent(scope.real, 'enforce_compliance_profile')

          profile_data = {}
          # Loop through all valid compliance profiles and merge them together in
          # order from first to last
          #
          # This needs to be in reverse so that we merge in the correct order
          Array(compliance_profile_to_enforce).reverse.each do |valid_profile|
            profile_data = {}

            # This backend makes assumptions that the compliance map files will be
            # named after the compliance profile that is to be enforced and that it
            # will be a YAML file.
            #
            # Therefore, we can simply look for that file under the available
            # backends and read it as appropriate.
            Backend.datasources(scope, order_override) do |source|
              data_file = Backend.datafile(:file, scope, source, 'yaml')

              next unless data_file
              next unless (File.basename(data_file) == "#{valid_profile}.yaml")
              next unless File.exist?(data_file)

              compliance_map = YAML.load_file(data_file)
              next unless compliance_map

              compliance_map = compliance_map['compliance_map']
              next unless compliance_map

              if (compliance_map[valid_profile] && compliance_map[valid_profile][key] && compliance_map[valid_profile][key].is_a?(Hash))

                profile_data = Backend.merge_answer(compliance_map[valid_profile], answer, { :behavior => 'deeper', :knockout_prefix => 'xx' })
              end
            end
          end

          if profile_data[key] && profile_data[key]['value']

            answer = Backend.parse_answer(profile_data[key]['value'], scope, {}, context)
          end
        end

        if resolution_type == :array
          answer = []
        elsif resolution_type.is_a?(Hash) || (resolution_type == :hash)
          answer = {}
        elsif answer == ''
          answer = nil
        end

        throw :no_such_key unless answer
        return answer
      end

      private

      # Hack to work around global warning qualified variable warnings
      def lookup_global_silent(scope, param)
        scope.find_global_scope.to_hash[param]
      end
    end
  end
end
