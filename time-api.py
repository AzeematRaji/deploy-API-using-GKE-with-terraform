from flask import Flask
from datetime import datetime

app = Flask(__name__)

@app.route('/time', methods=['GET'])
def get_time():
    return {'current_time': datetime.now().strftime("%Y-%m-%d %H:%M:%S")}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)