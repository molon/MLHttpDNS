Pod::Spec.new do |s|
s.name         = "MLHttpDNS"
s.version      = "0.0.2"
s.summary      = "MLHttpDNS"

s.homepage     = 'https://github.com/molon/MLHttpDNS'
s.license      = { :type => 'MIT'}
s.author       = { "molon" => "dudl@qq.com" }

s.source       = {
:git => "https://github.com/molon/MLHttpDNS.git",
:tag => "#{s.version}"
}

s.requires_arc  = true
s.platform     = :ios, '7.0'
s.public_header_files = 'Classes/**/*.h'
s.source_files  = 'Classes/**/*.{h,m}'

s.dependency 'AFNetworking' , '~> 3.1.0'
s.dependency 'YYCache', '~> 1.0.4'

end
