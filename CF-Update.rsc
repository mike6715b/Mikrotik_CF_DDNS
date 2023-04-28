#########################################################################
#         ==================================================            #
#         $ Mikrotik RouterOS update script for CloudFlare $            #
#         ==================================================            #
#                                                                       #
# - You need a CloudFlare account & api key (look under settings),      #
#   a zone and A record in it                                           #
# - All variables in first section are obvious,                         #
#   except CFid and CFzoneid                                            #
# - Obtain CFzoneid from Cloudflare Dashboard,                          #
#   on Overview tab scroll down                                         # 
#   To obtain CFid use following command in any unix shell:             #
#    curl -X GET "https://api.cloudflare.com/client/v4/zones/YOUR_ZONE_ID/dns_records?name=YOUR_DOMAIN" -H "Authorization:Bearer $CFtkn" -H "Content-Type: application/json" | python -mjson.tool
# - You can use my Postman script to get those variables                #
# - Enable CFDebug if needed - it'll print some info to logs            #
# - Enable CFcloud if you don't get a public IP on interface            #
# - Put script under /system scripts giving "read,write,ftp" policy access.       #
#   For 6.29 and older "test" policy is also needed.                    #
# - Add script to /system scheduler using it's name in "on-event"       #
# - Requires at least RouterOS 6.44beta75 for multiple header support   #
#                                                                       #
#              Credits for Samuel Tegenfeldt, CC BY-SA 3.0              #
#                        Modified by kiler129                           #
#                        Modified by viritt                             #
#                        Modified by asuna                              #
#                        Modified by mike6715b                          #
#                                                                       #
#               Tested and working as of February 22, 2021              #
#########################################################################

################# CloudFlare variables #################
:local CFDebug "false"
:local CFcloud "false"

:global WANInterface "WAN_INTERFACE"

:local CFdomain "YOUR_DOMAIN"

:local CFtkn "YOUR_API_TOKEN"

:local CFzoneid "ZONE_ID"
:local CFid "RECORD_ID"

:local CFrecordType ""
:set CFrecordType "A"

:local CFrecordTTL ""
:set CFrecordTTL "120"

#########################################################################
########################  DO NOT EDIT BELOW  ############################
#########################################################################

:log info "Updating $CFdomain ..."

################# Internal variables #################
:local previousIP ""
:global WANip ""

################# Build CF API Url (v4) #################
:local CFurl "https://api.cloudflare.com/client/v4/zones/"
:set CFurl ($CFurl . "$CFzoneid/dns_records/$CFid");
 
################# Get or set previous IP-variables #################
:if ($CFcloud = "true") do={
    :set WANip [/ip cloud get public-address]
};

:if ($CFcloud = "false") do={
    :local currentIP [/ip address get [/ip address find interface=$WANInterface ] address];
    :set WANip [:pick $currentIP 0 [:find $currentIP "/"]];
};

:if ([/file find name=ddns.tmp.txt] = "") do={
    :log error "No previous ip address file found, createing..."
    :set previousIP $WANip;
    :execute script=":put $WANip" file="ddns.tmp";
    :log info ("CF: Updating CF, setting $CFDomain = $WANip")
    /tool fetch http-method=put mode=https output=none url="$CFurl" http-header-field="Authorization:Bearer $CFtkn,content-type:application/json" http-data="{\"type\":\"$CFrecordType\",\"name\":\"$CFdomain\",\"ttl\":$CFrecordTTL,\"content\":\"$WANip\"}"
    :error message="No previous ip address file found."
} else={
    :if ( [/file get [/file find name=ddns.tmp.txt] size] > 0 ) do={ 
    :global content [/file get [/file find name="ddns.tmp.txt"] contents] ;
    :global contentLen [ :len $content ] ;  
    :global lineEnd 0;
    :global line "";
    :global lastEnd 0;   
            :set lineEnd [:find $content "\n" $lastEnd ] ;
            :set line [:pick $content $lastEnd $lineEnd] ;
            :set lastEnd ( $lineEnd + 1 ) ;   
            :if ( [:pick $line 0 1] != "#" ) do={   
                #:local previousIP [:pick $line 0 $lineEnd ]
                :set previousIP [:pick $line 0 $lineEnd ];
                :set previousIP [:pick $previousIP 0 [:find $previousIP "\r"]];
            }
    }
}

######## Write debug info to log #################
:if ($CFDebug = "true") do={
 :log info ("CF: hostname = $CFdomain")
 :log info ("CF: previousIP = $previousIP")
 :log info ("CF: currentIP = $currentIP")
 :log info ("CF: WANip = $WANip")
 :log info ("CF: CFurl = $CFurl&content=$WANip")
 :log info ("CF: Command = \"/tool fetch http-method=put mode=https url=\"$CFurl\" http-header-field="Authorization:Bearer $CFtkn,content-type:application/json" output=none http-data=\"{\"type\":\"$CFrecordType\",\"name\":\"$CFdomain\",\"ttl\":$CFrecordTTL,\"content\":\"$WANip\"}\"")
};
  
######## Compare and update CF if necessary #####
:if ($previousIP != $WANip) do={
 :log info ("CF: Updating CF, setting $CFDomain = $WANip")
 /tool fetch http-method=put mode=https url="$CFurl" http-header-field="Authorization:Bearer $CFtkn,content-type:application/json" output=none http-data="{\"type\":\"$CFrecordType\",\"name\":\"$CFdomain\",\"ttl\":$CFrecordTTL,\"content\":\"$WANip\"}"
 /ip dns cache flush
    :if ( [/file get [/file find name=ddns.tmp.txt] size] > 0 ) do={
        /file remove ddns.tmp.txt
        :execute script=":put $WANip" file="ddns.tmp"
    }
} else={
 :log info "CF: No Update Needed!"
}
