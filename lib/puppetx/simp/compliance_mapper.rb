# vim: set expandtab ts=2 sw=2:
def enforcement(key, &block)

  # Throw away keys we know we can't handle.
  # This also prevents recursion since these are the only keys internally we call.
  case key
  when "lookup_options"
    throw :key_error
  when "compliance_markup::compliance_map::percent_sign"
    throw :key_error
  when "compliance_markup::compliance_map"
    throw :key_error
  when "compliance_markup::enforcement"
    throw :key_error
  when "compliance_markup::version"
    throw :key_error
  else
    profile_list = @compliance_map_backend_cache[:profile_list]
    unless profile_list
      profile_list = yield "compliance_markup::enforcement", []
      @compliance_map_backend_cache[:profile_list] = profile_list
    end

    version = @compliance_map_backend_cache[:version]
    unless version
      version = yield "compliance_markup::version", "1.0.0"
      @compliance_map_backend_cache[:version] = version
    end

    retval = :notfound

    case version
    when /1.*/
      # This is for the version 1 compliance map format.
      module_scope_compliance_map = @compliance_map_backend_cache[:module_scope_compliance_map]
      unless module_scope_compliance_map
        module_scope_compliance_map = yield "compliance_markup::compliance_map", {}
        @compliance_map_backend_cache[:module_scope_compliance_map] = module_scope_compliance_map
      end

      top_scope_compliance_map = @compliance_map_backend_cache[:top_scope_compliance_map]
      unless top_scope_compliance_map
        top_scope_compliance_map = yield "compliance_map", {}
        @compliance_map_backend_cache[:top_scope_compliance_map] = top_scope_compliance_map
      end

      v1_compliance_map = @compliance_map_backend_cache[:v1_compliance_map]
      unless v1_compliance_map
        v1_compliance_map = {}
        v1_compliance_map.merge!(module_scope_compliance_map)
        v1_compliance_map.merge!(top_scope_compliance_map)
        @compliance_map_backend_cache[:v1_compliance_map] = v1_compliance_map
      end

      profile_list.each do |profile|
        if (profile != /^v[0-9]+/)
          if (v1_compliance_map.key?(profile))
            # Handle a knockout prefix
            if (v1_compliance_map[profile].key?("--" + key))
              break
            end
            if (v1_compliance_map[profile].key?(key))
              if (v1_compliance_map[profile][key].key?("value"))
                retval = v1_compliance_map[profile][key]["value"]
                break
              end
            end
          end
        end
      end
    else
    end

    if (retval == :notfound)
      throw :key_error
    end
  end
  return retval
end
