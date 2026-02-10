import sys, json
try:
    data = json.load(sys.stdin)
    if 'result' in data:
        print(data['result'][0])
    else:
        print("ERROR_JSON")
except:
    print("ERROR_PYTHON")