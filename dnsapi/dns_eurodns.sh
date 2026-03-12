#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_eurodns_info='EuroDNS
Site: eurodns.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_eurodns
Options:
 EURODNS_APP_ID Application ID
 EURODNS_API_KEY API Key
 EURODNS_TTL TTL. Default: "600".
Issues: github.com/acmesh-official/acme.sh/issues
Author: Nicolas Santorelli
'

#
# EuroDNS DNS API
#
# Report Bugs here: https://github.com/acmesh-official/acme.sh/issues
#
# EuroDNS API documentation:
# https://docapi.eurodns.com
#
# Usage:
#   export EURODNS_APP_ID="your-app-id"
#   export EURODNS_API_KEY="your-api-key"
#   acme.sh --issue --dns dns_eurodns -d example.com -d *.example.com
#
# The credentials will be saved in ~/.acme.sh/account.conf
#
# Optional:
#   export EURODNS_API_URL="https://rest-api.eurodns.com"  # Default API URL
#   export EURODNS_TTL=600  # Default TTL (minimum 600 for EuroDNS)
#

EURODNS_API_DEFAULT="https://rest-api.eurodns.com"
EURODNS_TTL_DEFAULT=600

########  Public functions #####################

#Usage: dns_eurodns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_eurodns_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using EuroDNS DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  EURODNS_APP_ID="${EURODNS_APP_ID:-$(_readaccountconf_mutable EURODNS_APP_ID)}"
  EURODNS_API_KEY="${EURODNS_API_KEY:-$(_readaccountconf_mutable EURODNS_API_KEY)}"
  EURODNS_API_URL="${EURODNS_API_URL:-$(_readaccountconf_mutable EURODNS_API_URL)}"
  EURODNS_API_URL="${EURODNS_API_URL:-$EURODNS_API_DEFAULT}"
  EURODNS_TTL="${EURODNS_TTL:-$(_readaccountconf_mutable EURODNS_TTL)}"
  EURODNS_TTL="${EURODNS_TTL:-$EURODNS_TTL_DEFAULT}"

  if [ -z "$EURODNS_APP_ID" ] || [ -z "$EURODNS_API_KEY" ]; then
    EURODNS_APP_ID=""
    EURODNS_API_KEY=""
    _err "You didn't specify EuroDNS App ID and API Key."
    _err "Please export EURODNS_APP_ID and EURODNS_API_KEY and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable EURODNS_APP_ID "$EURODNS_APP_ID"
  _saveaccountconf_mutable EURODNS_API_KEY "$EURODNS_API_KEY"
  if [ "$EURODNS_API_URL" != "$EURODNS_API_DEFAULT" ]; then
    _saveaccountconf_mutable EURODNS_API_URL "$EURODNS_API_URL"
  fi
  if [ "$EURODNS_TTL" != "$EURODNS_TTL_DEFAULT" ]; then
    _saveaccountconf_mutable EURODNS_TTL "$EURODNS_TTL"
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  _info "Adding TXT record"
  if _eurodns_add_txt_record "$_domain" "$_sub_domain" "$txtvalue"; then
    _info "Added TXT record successfully."
    return 0
  else
    _err "Failed to add TXT record."
    return 1
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_eurodns_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using EuroDNS DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  EURODNS_APP_ID="${EURODNS_APP_ID:-$(_readaccountconf_mutable EURODNS_APP_ID)}"
  EURODNS_API_KEY="${EURODNS_API_KEY:-$(_readaccountconf_mutable EURODNS_API_KEY)}"
  EURODNS_API_URL="${EURODNS_API_URL:-$(_readaccountconf_mutable EURODNS_API_URL)}"
  EURODNS_API_URL="${EURODNS_API_URL:-$EURODNS_API_DEFAULT}"

  if [ -z "$EURODNS_APP_ID" ] || [ -z "$EURODNS_API_KEY" ]; then
    EURODNS_APP_ID=""
    EURODNS_API_KEY=""
    _err "You didn't specify EuroDNS App ID and API Key."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  _info "Removing TXT record"
  if _eurodns_rm_txt_record "$_domain" "$_sub_domain" "$txtvalue"; then
    _info "Removed TXT record successfully."
    return 0
  else
    _err "Failed to remove TXT record."
    return 1
  fi
}

####################  Private functions below ##################################

# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _eurodns_rest GET "dns-zones/$h"; then
      _debug "Domain $h not found, continuing..."
      p=$i
      i=$(_math "$i" + 1)
      continue
    fi

    if _contains "$response" '"name"'; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain=$h
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}

# Add TXT record
_eurodns_add_txt_record() {
  domain=$1
  subdomain=$2
  txtvalue=$3

  _debug "Getting current zone data for $domain"

  if ! _eurodns_rest GET "dns-zones/$domain"; then
    _err "Failed to get zone data"
    return 1
  fi

  zone_data="$response"
  _debug2 zone_data "$zone_data"

  # Build new TXT record (minimum TTL for EuroDNS is 600)
  new_record='{"type":"TXT","host":"'"$subdomain"'","rdata":"'"$txtvalue"'","ttl":'"$EURODNS_TTL"'}'

  # Extract existing records array content from zone JSON
  # The API returns a single-line JSON, so we extract between "records":[ and the matching ]
  records_content=$(printf "%s" "$zone_data" | sed 's/.*"records"[[:space:]]*:[[:space:]]*\[//;s/\].*"urlForwards".*//')

  # Extract other required fields from zone data
  domain_connect=$(echo "$zone_data" | sed -n 's/.*"domainConnect"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p')
  url_forwards=$(echo "$zone_data" | sed -n 's/.*"urlForwards"[[:space:]]*:[[:space:]]*\(\[[^]]*\]\).*/\1/p')
  mail_forwards=$(echo "$zone_data" | sed -n 's/.*"mailForwards"[[:space:]]*:[[:space:]]*\(\[[^]]*\]\).*/\1/p')

  # Default values if not found
  domain_connect=${domain_connect:-false}
  url_forwards=${url_forwards:-[]}
  mail_forwards=${mail_forwards:-[]}

  # Build new zone data
  if [ -n "$records_content" ] && [ "$records_content" != "null" ]; then
    # Records exist, append new record
    new_zone_data='{"name":"'"$domain"'","domainConnect":'"$domain_connect"',"records":['"$records_content"','"$new_record"'],"urlForwards":'"$url_forwards"',"mailForwards":'"$mail_forwards"'}'
  else
    # Empty or no records, create new
    new_zone_data='{"name":"'"$domain"'","domainConnect":'"$domain_connect"',"records":['"$new_record"'],"urlForwards":'"$url_forwards"',"mailForwards":'"$mail_forwards"'}'
  fi

  _debug2 new_zone_data "$new_zone_data"

  # Validate zone first
  _debug "Validating zone"
  if ! _eurodns_rest POST "dns-zones/$domain/check" "$new_zone_data"; then
    _err "Zone validation failed"
    return 1
  fi

  # Check validation response
  if _contains "$response" '"valid"[[:space:]]*:[[:space:]]*false' || _contains "$response" '"error"'; then
    _err "Zone validation returned errors: $response"
    return 1
  fi

  # Save zone
  _debug "Saving zone"
  if ! _eurodns_rest PUT "dns-zones/$domain" "$new_zone_data"; then
    _err "Failed to save zone"
    return 1
  fi

  # Wait a bit for DNS propagation
  _sleep 2

  return 0
}

# Remove TXT record
_eurodns_rm_txt_record() {
  domain=$1
  subdomain=$2
  txtvalue=$3

  _debug "Getting current zone data for $domain"

  if ! _eurodns_rest GET "dns-zones/$domain"; then
    _err "Failed to get zone data"
    return 1
  fi

  zone_data="$response"
  _debug2 zone_data "$zone_data"

  # Extract existing records array content from zone JSON
  all_records=$(printf "%s" "$zone_data" | sed 's/.*"records"[[:space:]]*:[[:space:]]*\[//;s/\].*"urlForwards".*//')

  # Remove the matching TXT record object, then clean up commas
  records_content=$(printf "%s" "$all_records" | sed 's/{[^}]*"type":"TXT"[^}]*"host":"'"$subdomain"'"[^}]*"rdata":"'"$txtvalue"'"[^}]*}//g' | sed 's/,,/,/g;s/^\[,/[/;s/,\]/]/;s/^,//;s/,$//')

  if [ "$records_content" = "$all_records" ]; then
    _info "TXT record not found or already removed"
  fi

  # Extract other required fields
  domain_connect=$(echo "$zone_data" | sed -n 's/.*"domainConnect"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p')
  url_forwards=$(echo "$zone_data" | sed -n 's/.*"urlForwards"[[:space:]]*:[[:space:]]*\(\[[^]]*\]\).*/\1/p')
  mail_forwards=$(echo "$zone_data" | sed -n 's/.*"mailForwards"[[:space:]]*:[[:space:]]*\(\[[^]]*\]\).*/\1/p')

  # Default values
  domain_connect=${domain_connect:-false}
  url_forwards=${url_forwards:-[]}
  mail_forwards=${mail_forwards:-[]}

  # Build new zone data
  new_zone_data='{"name":"'"$domain"'","domainConnect":'"$domain_connect"',"records":['"$records_content"'],"urlForwards":'"$url_forwards"',"mailForwards":'"$mail_forwards"'}'

  _debug2 new_zone_data "$new_zone_data"

  # Save updated zone
  _debug "Saving zone without TXT record"
  if ! _eurodns_rest PUT "dns-zones/$domain" "$new_zone_data"; then
    _err "Failed to save zone"
    return 1
  fi

  return 0
}

# Make API request with retry logic for rate limiting
# Usage: _eurodns_rest METHOD ENDPOINT [DATA]
_eurodns_rest() {
  method=$1
  endpoint=$2
  data="$3"
  max_retries=3
  retry_count=0

  export _H1="X-APP-ID: $EURODNS_APP_ID"
  export _H2="X-API-KEY: $EURODNS_API_KEY"
  export _H3="Content-Type: application/json"
  export _H4="Accept: application/json"

  url="$EURODNS_API_URL/$endpoint"

  _debug2 url "$url"
  _debug2 method "$method"
  _debug2 data "$data"

  while [ "$retry_count" -lt "$max_retries" ]; do
    if [ "$method" = "GET" ]; then
      response="$(_get "$url")"
    else
      response="$(_post "$data" "$url" "" "$method")"
    fi

    _ret="$?"
    _debug2 response "$response"

    if [ "$_ret" != "0" ]; then
      _err "Error calling API"
      return 1
    fi

    # Check for rate limiting (HTTP 429 or rate limit message)
    if _contains "$response" '"status"[[:space:]]*:[[:space:]]*429' || _contains "$response" '"rate.limit"' || _contains "$response" '"rateLimit"'; then
      retry_count=$(_math "$retry_count" + 1)
      if [ "$retry_count" -lt "$max_retries" ]; then
        wait_time=$(_math "$retry_count" \* 5)
        _info "Rate limited, waiting ${wait_time}s before retry..."
        _sleep "$wait_time"
        continue
      else
        _err "Max retries exceeded due to rate limiting"
        return 1
      fi
    fi

    # Check for API errors in response
    if _contains "$response" '"error"'; then
      # Don't fail on 404 during zone detection
      if [ "$method" = "GET" ] && _contains "$response" '"status"[[:space:]]*:[[:space:]]*404'; then
        return 1
      fi
      _err "API returned error: $response"
      return 1
    fi

    # Success - exit retry loop
    return 0
  done

  return 1
}
