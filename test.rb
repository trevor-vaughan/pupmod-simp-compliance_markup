(0...10).each do |seed|
require 'digest'
     puts Digest::SHA256.hexdigest(seed.to_s).hex % 59
end
