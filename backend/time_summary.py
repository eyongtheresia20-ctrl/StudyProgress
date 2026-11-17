import time
import urllib.request
import json
import sys
sys.path.append('.')

from app.services.auth_service import create_access_token

token = create_access_token(user_id=4, role='student')
t0 = time.time()
req = urllib.request.Request(
    'http://localhost:8000/ai/summary',
    data=json.dumps({'subject_name': 'Physique', 'topic_title': 'Production et transmission du son'}).encode('utf-8'),
    headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {token}'}
)
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode('utf-8'))
    t1 = time.time()
    print(f'Done in {t1 - t0:.2f} seconds!')
    print('Content length:', len(data.get('content', '')))
