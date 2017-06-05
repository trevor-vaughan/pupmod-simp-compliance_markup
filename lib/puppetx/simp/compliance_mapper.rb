# vim: set expandtab ts=2 sw=2:
def enforcement(key, &block)

  # Throw away keys we know we can't handle. 
  # This also prevents recursion since these are the only keys internally we call.
  case key
  when "lookup_options"
    throw KeyError
  when "compliance_markup::compliance_map"
    throw KeyError
  when "compliance_markup::enforcement"
    throw KeyError
  when "compliance_markup::version"
    throw KeyError
  else
    profile_list = yield "compliance_markup::enforcement", []
    version = yield "compliance_markup::version", "1.0.0"
    retval = :notfound
    case version
    when /1.*/
      # This is for the version 1 compliance map format.
      module_scope_compliance_map = yield "compliance_markup::compliance_map", {}
      top_scope_compliance_map = yield "compliance_map", {}
      v1_compliance_map = {}
      v1_compliance_map.merge!(module_scope_compliance_map)
      v1_compliance_map.merge!(top_scope_compliance_map)

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
      throw KeyError
    end
  end
  return retval
end
