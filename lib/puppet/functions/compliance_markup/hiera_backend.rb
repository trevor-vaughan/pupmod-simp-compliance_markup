Puppet::Functions.create_function(:'compliance_markup::hiera_backend') do
	dispatch :hiera_backend do
		param "String", :key
		param "Puppet::LookupContext", :context
	end
	filename = File.dirname(File.dirname(File.dirname(File.dirname(__FILE__)))) + "/puppetx/simp/compliance_mapper.rb"
        self.class_eval(File.read(filename),filename)
	def hiera_backend(key, context)
		begin
			enforcement(key) do |key, default|
				call_function('lookup', key, { "default_value" => default})

			end
		rescue
			context.not_found
		end
	end
end
