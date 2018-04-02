Puppet::Type.newtype(:compliance_markup_shim) do

  desc <<-EOT
  Shim code for enabling the compliance markup functionality.
  EOT

  newparam(:name, :namevar => true) do
    desc 'An arbitrary name used as the identity of the resource.'
  end

  newproperty(:options, :array_matching => :all) do
    def retrieve
      true
    end

    def insync?(is)
      true
    end

    def set
      true
    end
  end

  autorequire(:file) do
    #
    # Dynamic per-environment code loader.
    #
    # XXX ToDo
    # This is persisted into the catalog ONLY to support compliance report
    # custom entries.
    #
    # See the compliance_map.rb source code, but these may not be necessary.
    # If that functionality is removed, return this logic to being instantiated each time.

    begin
      compliance_report_generator = catalog.environment_instance._compliance_report_generator
    rescue
      catalog.environment_instance.instance_eval do
        def _compliance_report_generator()
          @_compliance_report_generator
        end
        def _compliance_report_generator=(value)
          @_compliance_report_generator = value
        end
      end
        object = Object.new()
        myself = __FILE__
        filename = File.dirname(File.dirname(File.dirname(myself))) + "/puppetx/simp/compliance_map.rb"
        object.instance_eval(File.read(filename), filename)
        filename = File.dirname(File.dirname(File.dirname(myself))) + "/puppetx/simp/compliance_mapper.rb"
        object.instance_eval(File.read(filename), filename)
        catalog.environment_instance._compliance_report_generator = object;
        compliance_report_generator = object;
    end

    if value(:options).first.is_a?(Hash)
      opts = value(:options).first
    else
      opts = value(:options).flatten
    end

    compliance_report_generator.compliance_map(
      opts,
      catalog.environment_instance.instance_variable_get("@compliance_markup_shim_#{name}_context")
    )

    '/__compliance_markup_shim__'
  end
end
