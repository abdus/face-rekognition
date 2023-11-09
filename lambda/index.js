import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { fetch } from "fetch-h2";
import { fromEnv } from "@aws-sdk/credential-providers";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  ScanCommand,
} from "@aws-sdk/lib-dynamodb";
import {
  RekognitionClient,
  IndexFacesCommand,
} from "@aws-sdk/client-rekognition";

// These will be set using environment variables (via TerraForm)
const REGION = process.env.AWS_REGION;
//const PROFILE = process.env.AWS_PROFILE;
const TABLE_NAME = process.env.TABLE_NAME;
const COLLECTION_NAME = process.env.COLLECTION_NAME;

const credentials = fromEnv();
//const credentials = fromIni({ profile: PROFILE });
const dynamoDB = new DynamoDBClient({ credentials, region: REGION });
const dynamoDoc = DynamoDBDocumentClient.from(dynamoDB);
const rekognition = new RekognitionClient({ credentials, region: REGION });

function md5(data) {
  return crypto.createHash("md5").update(data).digest("hex");
}

/**
 * @param {Buffer} image
 * @returns {Promise<void>}
 * @description Indexes a face in the collection
 */
async function indexImage(key, bucket) {
  try {
    const data = await rekognition.send(
      new IndexFacesCommand({
        CollectionId: COLLECTION_NAME,
        Image: { S3Object: { Name: key, Bucket: bucket } },
        ExternalImageId: md5(bucket + key),
      })
    );

    return data;
  } catch (err) {
    console.log("Error", err);
    throw err;
  }
}

/**
 * store rekognition information to DynamoDB
 * @param {Object} data - rekognition data
 * @param {String} individualName - name of the individual
 * @returns {Promise<void>}
 */
async function pushToDynamoDB(data, individualName, imageARN) {
  try {
    if (
      !data.FaceRecords[0] ||
      !data.FaceRecords[0].Face ||
      !data.FaceRecords[0].Face.FaceId
    ) {
      throw new Error("FaceId is not found");
    }

    const putCommand = new PutCommand({
      TableName: TABLE_NAME,
      Item: {
        name: individualName,
        image: imageARN,
        faceId: data.FaceRecords[0].Face.FaceId,
        externalImageId: data.FaceRecords[0].Face.ExternalImageId,
        createdTimestamp: Date.now(),
      },
    });

    return dynamoDoc.send(putCommand);
  } catch (err) {
    console.log("Error", err);
    throw err;
  }
}

/**
 * AWS Lambda handler function that is invoked by an S3 event
 * @param {Object} event - S3 event object
 */
export async function faceIndexHandler(event) {
  try {
    if (!event.Records || !event.Records[0] || !event.Records[0].s3) {
      throw new Error("Invalid event");
    }

    const key = decodeURIComponent(event.Records[0].s3.object.key);
    const bucket = decodeURIComponent(event.Records[0].s3.bucket.name);
    const s3ImageARN = `arn:aws:s3:::${bucket}/${key}`;
    const individualName = key.split("/").shift();

    if (!individualName) throw new Error("Invalid file name");

    const response = await indexImage(key, bucket);
    console.log(`indexed ${key} to ${COLLECTION_NAME}`);
    await pushToDynamoDB(response, individualName, s3ImageARN);
    console.log(`pushed ${key} to ${TABLE_NAME}`);

    return response;
  } catch (err) {
    console.log(err);
    throw err;
  }
}

/**
 * AWS Lambda handler function that is invoked by an API Gateway event
 * @param {Object} event - API Gateway event object
 */
export async function apiHandler(event) {
  try {
    const img = event.body.imageURL;
    const resp = await fetch(img);
    const arrayBuffer = await resp.arrayBuffer();
    const imageBuffer = Buffer.from(arrayBuffer);

    const data = await rekognition.send(
      new IndexFacesCommand({
        CollectionId: COLLECTION_NAME,
        Image: { Bytes: imageBuffer },
      })
    );

    if (
      !data.FaceRecords[0] ||
      !data.FaceRecords[0].Face ||
      !data.FaceRecords[0].Face.FaceId
    ) {
      throw new Error("FaceId is not found");
    }

    const faceId = data.FaceRecords[0].Face.FaceId;
    const result = await dynamoDoc.send(
      new ScanCommand({
        TableName: TABLE_NAME,
        FilterExpression: "faceId = :faceId",
        ExpressionAttributeValues: { ":faceId": faceId },
      })
    );

    return {
      body: JSON.stringify(result.Items),
      statusCode: 200,
      headers: { "Content-Type": "application/json" },
    };
  } catch (err) {
    console.log("Error", err);
    throw err;
  }
}
