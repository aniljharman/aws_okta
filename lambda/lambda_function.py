import json
import time
import os
import boto3
import requests

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DDB_TABLE'])
SLACK_URL = os.environ['SLACK_WEBHOOK_URL']
THRESHOLD = int(os.environ.get("ALERT_THRESHOLD", 5))
WINDOW_SECONDS = int(os.environ.get("ALERT_WINDOW_SECONDS", 300))

def lambda_handler(event, context):
    body = json.loads(event['body'])

    if body.get("eventType") != "group.user_membership.remove":
        return {"statusCode": 200, "body": "Ignored"}

    group_info = next((t for t in body["target"] if t["type"] == "UserGroup"), None)
    if not group_info:
        return {"statusCode": 400, "body": "Invalid payload"}

    group_name = group_info["displayName"]
    timestamp = int(time.time())
    ttl = timestamp + WINDOW_SECONDS

    table.put_item(Item={
        "group_name": group_name,
        "timestamp": timestamp,
        "ttl": ttl
    })

    response = table.query(
        KeyConditionExpression="group_name = :g AND timestamp >= :start",
        ExpressionAttributeValues={
            ":g": group_name,
            ":start": timestamp - WINDOW_SECONDS
        }
    )

    if len(response['Items']) > THRESHOLD:
        msg = f":warning: *{len(response['Items'])}* users removed from *{group_name}* in the last 5 mins!"
        requests.post(SLACK_URL, json={"text": msg})

    return {"statusCode": 200, "body": "Processed"}
