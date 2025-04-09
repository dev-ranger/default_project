"""
꽃 이미지 분류 API 서버

이 모듈은 FastAPI를 사용하여 꽃 이미지 분류 API를 제공합니다.
TensorFlow SavedModel을 로드하여 이미지 분류를 수행합니다.
"""

import io
import logging
from typing import Dict, List, Tuple, Any

import numpy as np
import tensorflow as tf
import uvicorn
from fastapi import FastAPI, HTTPException, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
from tensorflow.keras.layers import TFSMLayer
import os

# 상수 정의
MODEL_PATH = "./"
MODEL_ENDPOINT = "serving_default"
HOST = "127.0.0.1"
PORT = 8000
IMAGE_SIZE = (224, 224)
NORMALIZATION_FACTOR = 255.0

# 꽃 클래스 정의
FLOWER_CLASSES = [
    "dandelion",
    "daisy",
    "tulips",
    "sunflowers",
    "roses",
]

# 로깅 설정
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# FastAPI 앱 생성
app = FastAPI(
    title="Flower Classification API",
    description="API for classifying flower images using TensorFlow model",
    version="1.0.0",
)

# CORS 설정
origins = ["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def load_model():
    model_path = os.path.expanduser('./base_model.keras')
    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model file not found: {model_path}")
    model = tf.keras.models.load_model(model_path)
    return model


def preprocess_image(image: Image.Image, target_size: Tuple[int, int] = IMAGE_SIZE) -> np.ndarray:
    """
    이미지 전처리 함수. RGB 변환, 리사이즈, 정규화를 수행합니다.

    Args:
        image (Image.Image): 처리할 PIL 이미지
        target_size (Tuple[int, int], optional): 타겟 이미지 크기. 기본값은 (224, 224)

    Returns:
        np.ndarray: 전처리된 이미지 배열

    Raises:
        ValueError: 이미지 전처리 실패 시 발생
    """
    try:
        # 이미지를 RGB로 변환
        image = image.convert("RGB")
        
        # 이미지 크기 조정
        image = image.resize(target_size)
        
        # 이미지 배열로 변환 및 정규화
        img_array = np.array(image, dtype=np.float32) / NORMALIZATION_FACTOR
        
        # 배치 차원 추가
        img_array = np.expand_dims(img_array, axis=0)
        
        return img_array
    except Exception as e:
        raise ValueError(f"이미지 전처리 실패: {e}")


def predict_image(image: Image.Image) -> Dict[str, float]:
    """
    전처리된 이미지에 대해 모델 예측을 수행합니다.

    Args:
        image (Image.Image): 예측할 PIL 이미지

    Returns:
        Dict[str, float]: 각 클래스별 예측 확률

    Raises:
        HTTPException: 예측 실패 시 발생
    """
    try:
        # 이미지 전처리
        preprocessed_img = preprocess_image(image)
        logger.info(
            f"전처리된 이미지 형태: {preprocessed_img.shape}, 데이터 타입: {preprocessed_img.dtype}"
        )
        
        # 모델 예측 수행
        try:
            predictions = model(preprocessed_img, training=False)  # 모델 호출
            logger.info(f"예측 결과 딕셔너리 키: {predictions.keys()}")
            
            # 모델 출력 키 확인
            output_key = list(predictions.keys())[0]  # 첫 번째 키 사용
            outputs = predictions[output_key]  # 출력 값 가져오기
            logger.info(f"모델 출력: {outputs.numpy()}")
            
            # 확률화
            probabilities = tf.nn.softmax(outputs[0]).numpy()
        except Exception as prediction_error:
            logger.error(f"모델 호출 실패: {prediction_error}")
            raise HTTPException(
                status_code=500, detail="모델 예측에 실패했습니다."
            )
        
        # 클래스 매핑
        class_probabilities = dict(zip(FLOWER_CLASSES, probabilities.tolist()))
        logger.info(f"최종 예측 결과: {class_probabilities}")
        
        return class_probabilities
    except Exception as e:
        logger.error(f"예측 실패: {e}", exc_info=True)
        raise HTTPException(
            status_code=500, detail=f"예측 실패: {str(e)}"
        )


# 모델 로드
model = load_model()


@app.get("/")
async def get_root():
    """API 루트 엔드포인트

    Returns:
        str: 웰컴 메시지
    """
    logger.info("루트 URL 요청됨")
    return "꽃 이미지 분류 API에 오신 것을 환영합니다!"


@app.post("/predict")
async def predict_flower(file: UploadFile = File(...)) -> Dict[str, Any]:
    """
    업로드된 이미지에 대한 모델 예측을 수행합니다.

    Args:
        file (UploadFile): 업로드된 이미지 파일

    Returns:
        Dict[str, Any]: 예측 결과가 포함된 딕셔너리

    Raises:
        HTTPException: 예측 실패 시 발생
    """
    try:
        contents = await file.read()
        image = Image.open(io.BytesIO(contents)).convert("RGB")
        logger.info("이미지 업로드 성공")
        
        # 예측 수행
        result = predict_image(image)
        return {"predictions": result}
    except Exception as e:
        logger.error(f"예측 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(
        "server_fastapi_iamge_model:app",
        reload=True,  # 코드 변경 시 자동 리로드
        host=HOST,
        port=PORT,
        log_level="info",  # 로깅 레벨
    )
