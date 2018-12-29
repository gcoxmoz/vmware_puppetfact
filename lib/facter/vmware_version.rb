# This file was generated from templates/vmware_version.rb

require 'facter'

if Facter.value(:kernel) == 'Linux'
    Facter.loadfacts()
    
    hasdmidecode = Facter::Util::Resolution.exec('which dmidecode')
    if !hasdmidecode.nil?
        biosinformation = Facter::Util::Resolution.exec("#{hasdmidecode} -t bios | grep -A4 'BIOS Information'")
        if !biosinformation.nil?

            if biosinformation.include? 'Address: 0x'
                biosaddress = biosinformation.match(/Address: (0x.*)/i)[1]
            else
                biosaddress = 'no_data'
            end
            if biosinformation.include? 'Release Date:'
                biosdate = biosinformation.match(/Release Date: (.*)/i)[1]
            else
                biosdate = 'no_data'
            end

            if biosaddress == 'no_data'
                vmversion = "unknown-#{biosaddress}"
#           Numbers from a prior life, which have only anecdotal proof.  Uncomment if you wish
#            elsif biosaddress == '0xE8480'
#                vmversion = '2.5'
#            elsif biosaddress == '0xE7C70'
#                vmversion = '3.0'
#            elsif biosaddress == '0xE7910'
#                vmversion = '3.5'
            elsif biosaddress == '0xEA550'
                vmversion = '4.0'
            elsif biosaddress == '0xEA2E0'
                vmversion = '4.1'
            elsif biosaddress == '0xE72C0'
                vmversion = '5.0'
            elsif biosaddress == '0xEA0C0'
                vmversion = '5.1'
            elsif biosaddress == '0xE9AB0'
                vmversion = '5.1'
            elsif biosaddress == '0xEA050'
                vmversion = '5.5'
            elsif biosaddress == '0xE9FE0'
                vmversion = '5.5'
            elsif biosaddress == '0xE9A40'
                vmversion = '6.0'
            elsif biosaddress == '0xE99E0'
                vmversion = '6.0'
            elsif biosaddress == '0xEA580'
                vmversion = '6.5'
            elsif biosaddress == '0xEA520'
                vmversion = '6.7'
            else
                vmversion = "unknown-#{biosaddress}"
            end

            Facter.add('vmware_version') do
                confine :virtual => :vmware
                setcode { vmversion }
            end
        end
    end
end
