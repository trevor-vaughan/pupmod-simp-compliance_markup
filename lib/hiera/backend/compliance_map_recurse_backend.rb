class Hiera
  module Backend
    class Compliance_map_recurse_backend
      require 'deep_merge'

      def initialize
        Hiera.debug('Hiera Compliance Map Recurse backend starting')

        @@compliance_map_recurse_lock = nil
        @@compliance_map_cache = {}
      end

      def lookup(key, scope, order_override, resolution_type, context)
        Hiera.debug("Looking up #{key} in Compliance Map Recurse backend")

        answer = nil

        if @@compliance_map_recurse_lock
          @@compliance_map_recurse_lock = nil

          Hiera.debug('Compliance Map avoiding recursion loop')

          return nil
        end

        @@compliance_map_recurse_lock = true

        if Object.const_defined?('Puppet') && scope.respond_to?(:real)
          compliance_profile_to_enforce = lookup_global_silent(scope.real, 'enforce_compliance_profile')

          # We're being called from Puppet, so we should try to look things up
          # appropriately
          if !compliance_profile_to_enforce && scope.real.respond_to?(:call_function)
            begin
              # Puppet 4
              compliance_profile_to_enforce = scope.real.call_function('lookup',['enforce_compliance_profile'])
            rescue NoMethodError, Puppet::ParseError
              compliance_profile_to_enforce = nil
            end
          end

          # Loop through all valid compliance profiles and merge them together in
          # order from first to last
          #
          # This needs to be in reverse so that we merge in the correct order
          Array(compliance_profile_to_enforce).reverse.each do |valid_profile|
            answer ||= {}

            if @@compliance_map_cache[valid_profile]
                @@compliance_map_cache[valid_profile] = compliance_map[valid_profile]

                Backend.merge_answer(@@compliance_map_cache[valid_profile], answer, { :behavior => 'deeper', :knockout_prefix => 'xx' })
            else
              compliance_map = Backend.lookup('compliance_map', nil, scope.real, order_override, :hash)
              if compliance_map.is_a?(Hash) && compliance_map[valid_profile]
                if (compliance_map[valid_profile][key].is_a?(Hash) && compliance_map[valid_profile][key])
                  @@compliance_map_cache[valid_profile] = compliance_map[valid_profile]

                  Backend.merge_answer(@@compliance_map_cache[valid_profile], answer, { :behavior => 'deeper', :knockout_prefix => 'xx' })
                end
              end
            end
          end
        end

        # Reset for future calls
        @@compliance_map_recurse_lock = nil
        @@compliance_map_cache = {}

        if answer[key] && answer[key]['value'] && (answer[key]['value'] != '')
          answer = Backend.parse_answer(answer[key]['value'], scope, {}, context)
        else
          answer = nil
        end

        if resolution_type == :array
          answer = []
        elsif resolution_type.is_a?(Hash) || (resolution_type == :hash)
          answer = {}
        elsif answer == ''
          answer = nil
        end

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
