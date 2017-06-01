# vim: set expandtab ts=2 sw=2:
def enforcement(key, &block)
  case key
  when "lookup_options"
    throw KeyError
  when "compliance_markup::compliance_map"
    throw KeyError
  when "compliance_markup::enforcement"
    throw KeyError
  else
    hiera_compliance_map = yield "compliance_markup::compliance_map", {}
    profile_list = yield "compliance_markup::enforcement", []
    retval = :notfound

    profile_list.each do |profile|
      if (hiera_compliance_map.key?(profile))
        if (hiera_compliance_map[profile].key?(key))
          if (hiera_compliance_map[profile][key].key?("value"))
            retval = hiera_compliance_map[profile][key]["value"]
            break
          end
        end
      end
    end
    if (retval == :notfound)
      throw KeyError
    end
  end
  return retval
end
