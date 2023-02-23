import json
import sys
from base64 import b64encode, b64decode

#hex = '1369ace1025b26fbc6e88f3fb31ff557254a600d95496bd5fd36488d12396411'

try:
    hex = sys.argv[sys.argv.index('--txid') + 1]
except (ValueError, IndexError):
    print('No TXID given.')
    sys.exit(0)

b64 = b64encode(bytes.fromhex(hex)).decode()
#print('TXID:',b64)
#print(json.dumps({'txid_base64': b64, 'txid': hex}))
print(json.dumps({'txid_base64': "ORD:{}".format(b64), 'txid': hex}))
