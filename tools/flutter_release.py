import json, urllib.request
data=json.load(urllib.request.urlopen('https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json', timeout=30))
base=data['base_url']
for r in data['releases']:
    if r['channel']=='stable' and r['dart_sdk_arch']=='x64':
        print(r['version'], r['archive'], base+'/'+r['archive'], r['release_date']); break
