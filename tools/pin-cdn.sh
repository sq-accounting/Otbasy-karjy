#!/usr/bin/env bash
# ============================================================================
#  CDN скрипттерін нақты нұсқаға бекіту + SRI (Subresource Integrity) қосу.
#
#  Неге керек: қазір index.html Supabase SDK мен Chart.js-ті @2 / @4 (жылжымалы)
#  күйінде жүктейді. Нақты нұсқаға бекіту + SRI хэші CDN бұзылса да бөтен кодтың
#  жүктелмеуін қамтамасыз етеді (браузер хэш сәйкес келмесе скриптті іске қоспайды).
#
#  Бұл скриптті ИНТЕРНЕТІ БАР машинада іске қосыңыз — ол нақты нұсқаларды тауып,
#  sha384 есептеп, index.html-ге қоятын дайын <script> тегтерін басып шығарады.
#
#  Қолдану:
#     bash tools/pin-cdn.sh
#  Сосын шыққан екі жолды index.html ішіндегі ескі <script ...supabase...> және
#  <script ...chart.js...> жолдарының орнына қойыңыз.
# ============================================================================
set -euo pipefail

pin () {
  local pkg="$1" range="$2"
  # jsdelivr нақты шешілген нұсқаны қайтарады
  local resolved
  resolved=$(curl -fsSL "https://data.jsdelivr.com/v1/packages/npm/${pkg}/resolved?specifier=${range}" \
             | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
  if [ -z "$resolved" ]; then echo "!! ${pkg}: нұсқа табылмады" >&2; return 1; fi
  local url="https://cdn.jsdelivr.net/npm/${pkg}@${resolved}"
  local hash
  hash=$(curl -fsSL "$url" | openssl dgst -sha384 -binary | openssl base64 -A)
  echo "<script src=\"${url}\" integrity=\"sha384-${hash}\" crossorigin=\"anonymous\" referrerpolicy=\"no-referrer\"></script>"
}

echo "# index.html-ге қойыңыз (ескі екі <script> тегінің орнына):"
echo
pin "@supabase/supabase-js" "2"
pin "chart.js" "4"
