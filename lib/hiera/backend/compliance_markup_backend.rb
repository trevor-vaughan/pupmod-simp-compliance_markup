# vim: set expandtab ts=2 sw=2:
class Hiera
  module Backend
    class Compliance_markup_backend
      module Puppet::Pops::Lookup
        # Puppet 4.10+ added a name stack to ensure that there aren't lookup loops.
        #
        # However, we use recursion in our stack, so we need to override this
        # and catch items if they go too far down the stack
        module ComplianceMapExtensions
          def check(name)
            @compliance_map_to_ignore = {
              'compliance_map' => {
                :count => 0
              },
              'enforce_compliance_profile' => {
                :count => 0
              },
              'compliance_markup::enforce_profiles' => {
                :count => 0
              },
              'compliance_markup::compliance_map' => {
                :count => 0
              }
            }

            if @compliance_map_to_ignore[name]
              @compliance_map_to_ignore[name][:count] += 1

              if @compliance_map_to_ignore[name][:count] > 1
                raise Puppet::DataBinding::RecursiveLookupError, "Recursive lookup detected in [#{@name_stack.join(', ')}"
              end
            end

            if @name_stack
              @name_stack = (@name_stack - @compliance_map_to_ignore.keys)
            end

            super
          end
        end

        Invocation.prepend ComplianceMapExtensions
      end

      require 'deep_merge'
      def initialize
        filename = File.dirname(File.dirname(File.dirname(__FILE__))) + "/puppetx/simp/compliance_mapper.rb"

        self.instance_eval(File.read(filename),filename)

        Hiera.debug('Hiera Compliance Map backend starting')
        @compliance_map_recursion_lock = false
        @compliance_map_backend_cache = {}
      end

      def lookup(key, scope, order_override, resolution_type, context)
        answer = :not_found
        if @compliance_map_recursion_lock
          Hiera.debug("Compliance Map avoiding recursion loop while looking for #{key}")
          throw :no_such_key
        end

        catch(:key_error) do
          @compliance_map_recursion_lock = true
          answer = enforcement(key) do |lookup, default|
            rscope = scope.real
            rscope.call_function('lookup', [lookup, { "default_value" => default }])
          end
        end

        @compliance_map_recursion_lock = false

        if (answer == :not_found)
          throw :no_such_key
        end
        return answer
      end

      private

    end
  end
end
