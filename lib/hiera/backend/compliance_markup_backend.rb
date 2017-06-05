# vim: set expandtab ts=2 sw=2:
class Hiera
  module Backend
    class Compliance_markup_backend
      require 'deep_merge'
      def initialize
        filename = File.dirname(File.dirname(File.dirname(__FILE__))) + "/puppetx/simp/compliance_mapper.rb"
        self.instance_eval(File.read(filename),filename)
        Hiera.debug('Hiera Compliance Map backend starting')
        self.class.instance_variable_set('@compliance_map_recursion_lock', false)
      end

      def lookup(key, scope, order_override, resolution_type, context)
        answer = :not_found
        if (self.class.instance_variable_get('@compliance_map_recursion_lock'))
          Hiera.debug("Compliance Map avoiding recursion loop while looking for #{key}")

          throw :no_such_key
        end

        if (key == "lookup_options")
          throw :no_such_key
        end
        begin
          self.class.instance_variable_set('@compliance_map_recursion_lock', true)
          answer = enforcement(key) do |lookup, default|
            rscope = scope.real
            retval = rscope.call_function('lookup', [lookup, { "default_value" => default }])
          end
        rescue
            self.class.instance_variable_set('@compliance_map_recursion_lock', false)
            throw :no_such_key
        end
        self.class.instance_variable_set('@compliance_map_recursion_lock', false)
        if (answer == :not_found)
          throw :no_such_key
        end
        return answer
      end



















      def orig_lookup(key, scope, order_override, resolution_type, context)
        Hiera.debug("Looking up #{key} in Compliance Map backend")

        answer = nil

        if (self.class.instance_variable_get('@compliance_map_recursion_lock'))
          Hiera.debug("Compliance Map avoiding recursion loop while looking for #{key}")

          throw :no_such_key
        end

        # We need to do this to make sure that we clean up our lock
        catch(:compliance_map_escape) do
          if Object.const_defined?('Puppet') && Puppet.respond_to?(:lookup) && scope.respond_to?(:real)
            # Ensure that we don't end up in an endless lookup loop
            #
            # This is a *class* instance variable so it will get cleaned up on
            # class destruction, not class instance destruction
            self.class.instance_variable_set('@compliance_map_recursion_lock', true)

            # When this backend is called, we should have a resource in the
            # catalog called 'compliance_markup'
            #
            # If we do not, then we should continue since the user may be only
            # using the global entries
            #
            # It is, however, possible that they did not properly include the
            # compliance_markup::enforcement_helper before *everything* that
            # they want to enforce
            compliance_markup_resource = scope.catalog.resource('Class[compliance_markup]')
            compliance_enforce_resource = scope.catalog.resource('Class[compliance_markup::enforcement_helper]')

            # The following two items pull any global entries that might be set
            #
            # This is mainly for ENC compatibility
            global_profile_list = Array(retrieve_global(scope.real, 'enforce_compliance_profile'))
            module_profile_list = Array(retrieve_global(scope.real, 'compliance_markup::enforcement_helper::profiles'))

            if module_profile_list.empty? && compliance_enforce_resource
              module_profile_list = Array(compliance_enforce_resource[:profiles])
            end

            # Create an Array of all profiles that we want to enforce
            compliance_profiles_to_enforce = global_profile_list + module_profile_list

            # If we didn't find anything at global scope, we need to dig down
            # through the standard stack
            if !compliance_profiles_to_enforce || compliance_profiles_to_enforce.empty?
              begin
                global_profile_list = Array(scope.real.call_function('lookup',
                                                                     [
                                                                       'enforce_compliance_profile',
                                                                       {
                                                                         'default_value' => []
                                                                       }
                ]
                                                                    ))

                module_profile_list = Array(compliance_markup_resource[:enforce_profiles])

                compliance_profiles_to_enforce = global_profile_list + module_profile_list

              rescue NoMethodError, Puppet::ParseError
                compliance_profiles_to_enforce = []
              end
            end

            # If we don't have any profiles to enforce, then there is nothing to
            # look up and we can just bail
            throw :compliance_map_escape if compliance_profiles_to_enforce.empty?

            # Handle the ENC first
            global_map = retrieve_global(scope.real, 'compliance_map')

            # Look it up if we can't find it globally
            global_map ||= scope.real.call_function('lookup',
                                                    [
                                                      'compliance_map',
                                                      {
                                                        'merge' => 'deep',
                                                        'default_value' => {}
                                                      }
            ]
                                                   )

            # If we don't have a resource and we didn't find anything at the
            # Global level, then we can't find anything at all so bail
            throw :compliance_map_escape if (compliance_markup_resource.nil? && global_map.empty?)

            # Handle the ENC first
            module_map = retrieve_global(scope.real, 'compliance_markup::compliance_map')

            if compliance_markup_resource
              # Dig into the Resource
              module_map ||= compliance_markup_resource[:compliance_map]
            end

            # If, at this point, we don't have either a global map or a module
            # map with data in it, bail
            if (global_map.empty? && (module_map.nil? || module_map.empty?))
              throw :compliance_map_escape
            end

            answer = nil

            # Ensure that we get the most relevant value
            Array(compliance_profiles_to_enforce).each do |valid_profile|
              # TODO: At some point, we're going to need to handle value-centric
              # merge strategies but, for now, first one wins.

              # Break out if we found something on the last run
              break if answer

              [Hash(global_map), Hash(module_map)].each do |compliance_map|
                if compliance_map[valid_profile]
                  # Handle a knockout
                  if compliance_map[valid_profile]["--#{key}"]
                    throw :compliance_map_escape
                  end

                  if compliance_map[valid_profile][key].is_a?(Hash)
                    map_val = compliance_map[valid_profile][key]['value']
                    # The compliance map uses empty values as items to be ignored
                    #
                    # This probably needs to change in the future
                    if map_val && (map_val != '') && (map_val !~ /^re:/)
                      answer = map_val

                      break
                    end
                  end
                end
              end
            end
          end
        end

        # Reset for future calls

        throw :no_such_key unless answer

        answer = Backend.parse_answer(answer, scope.real, {}, context)

        if resolution_type == :array
          throw :no_such_key unless answer.is_a?(Array)
        elsif resolution_type.is_a?(Hash) || (resolution_type == :hash)
          throw :no_such_key unless answer.is_a?(Hash)
        end

        return answer
      end

      private

      # Hack to work around global warning qualified variable warnings
      def retrieve_global(scope, param)
        if scope.respond_to?(:real)
          scope.real.find_global_scope.to_hash[param]
        else
          scope.find_global_scope.to_hash[param]
        end
      end
    end
  end
end