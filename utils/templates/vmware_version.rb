require 'facter'

# TODO: Verify this is required for the confine to work correctly.
Facter.loadfacts()

Facter.add('vmware_version') do
    confine :kernel => 'Linux'
    confine :virtual => :vmware
    setcode {
        biosinformation = Facter::Util::Resolution.exec("dmidecode -t bios | grep -A4 'BIOS Information'")
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
            [PLACEHOLDER]
            else
                vmversion = "unknown-#{biosaddress}"
            end

            # The effective return:
            vmversion
        end
    }
end
