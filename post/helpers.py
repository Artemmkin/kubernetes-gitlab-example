import structlog
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure
from json import dumps
from flask import request


log = structlog.get_logger()


def http_healthcheck_handler(mongo_host, mongo_port, version):
    postdb = MongoClient(mongo_host, int(mongo_port),
                         serverSelectionTimeoutMS=2000)
    try:
        postdb.admin.command('ismaster')
    except ConnectionFailure:
        postdb_status = 0
    else:
        postdb_status = 1

    status = postdb_status
    healthcheck = {
        'status': status,
        'dependent_services': {
            'postdb': postdb_status
        },
        'version': version
    }
    return dumps(healthcheck)


def log_event(event_type, name, message, params={}):
    request_id = request.headers['Request-Id'] \
        if 'Request-Id' in request.headers else None
    if event_type == 'info':
        log.info(name, service='post', request_id=request_id,
                 message=message, params=params)
    elif event_type == 'error':
        log.error(name, service='post', request_id=request_id,
                  message=message, params=params)
