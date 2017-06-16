# vim: set expandtab ts=2 sw=2:
class Hiera
  module Backend
    class Compliance_markup_backend
      def initialize
        # 
        # Load the shared compliance_mapper codebase
        #
        filename = File.dirname(File.dirname(File.dirname(__FILE__))) + "/puppetx/simp/compliance_mapper.rb"
        self.instance_eval(File.read(filename), filename)

        # Grab the config from hiera
        @config = Config[:compliance_markup]

        @cache_timeout = @config[:cache_timeout] || 600
        @cache_clean_interval = @config[:cache_clean_interval] || 3600
        @cache_last_check = Time.now.to_i + @cache_clean_interval
      end

      def lookup(key, scope, order_override, resolution_type, context)
        # Monkey patch the catalog *object* to add a _compliance_cache accessor
        # We do this to prevent environment poisoning by monkey patching the class,
        # and it still allows us to have a catalog scoped cache.

        begin
          @cache = scope.catalog._compliance_cache
        rescue
          scope.catalog.instance_eval("
           def _compliance_cache=(value)
             @_compliance_cache = value
           end
           def _compliance_cache
             @_compliance_cache
           end")
          scope.catalog._compliance_cache = {}
          @cache = scope.catalog._compliance_cache
        end


        now = Time.now.to_i
        if (now > @cache_last_check)
          clean_cache(now)
        end

        answer = :not_found
        
        begin
          answer = enforcement(key) do |lookup, default|
            rscope = scope.real
            rscope.call_function('lookup', [lookup, { "default_value" => default }])
          end
        rescue => e
          unless (e.class.to_s == "ArgumentError")
            debug("Threw error #{e.to_s}")
          end
          throw :no_such_key
        end
        
        if (answer == :not_found)
          throw :no_such_key
        end
        
        return answer
      end


      #
      # These functions are helpers for enforcement(), that implement
      # the different caching systems on a v3 vs v5 backend
      #
      def debug(message)
        Hiera.debug(message)
      end

      # This cache is explicitly per-catalog
      def cache(key, value)
        expiration = Time.now.to_i + @cache_timeout
        object = {
          :expired_at => expiration,
          :data => value,
        }
        @cache[key] = object
      end
      def cached_value(key)
        @cache[key][:data]
      end
      def cache_has_key(key)
        retval = false
        if (@cache.key?(key))
          if (@cache[key][:expired_at] >= Time.now.to_i)
            retval = true
          end
        end
        retval
      end
      private
      def clean_cache(now)
        @cache.delete_if do |key, entry|
          entry[:expired_at] < now
        end
      end
    end
  end
end
