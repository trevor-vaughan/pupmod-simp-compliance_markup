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

      private

    end
  end
end
