# Qwen Edit-2511 체크포인트 테스트용 RunPod worker

## 준비 상태

실행 소스와 요청 예제만 준비됨. Docker 빌드, GPU 실행, 현재 학습 LoRA 호환성은 아직 검증되지 않음.
학습 서버에 접속하거나 학습을 중단하지 않는다. 이 패키지는 추론 전용이다.

## Docker Hub 없이 웹에서 배포

1. GitHub에 비공개 저장소를 만들고 이 폴더의 Dockerfile, requirements.txt, handler.py.in, .dockerignore를 저장소 최상위에 업로드한다. 프로젝트 전체나 인증정보는 올리지 않는다.
2. RunPod Settings → Connections에서 그 저장소만 접근하도록 GitHub를 연결한다.
3. Serverless → New Endpoint → Deploy from a GitHub repository에서 저장소와 브랜치, Dockerfile 경로 `Dockerfile`을 선택한다. RunPod가 이미지를 빌드하고 자체 레지스트리에 저장한다.
4. Queue, A100 80GB 또는 H100 80GB, GPU 1개, Active workers 0, Max workers 1, Idle timeout 5초, Execution timeout 1800초, FlashBoot 사용을 권장한다. 1800초는 최초 검증용 상한이지 예상 소요 시간이 아니다.
5. 해당 GPU를 사용할 수 있는 데이터센터의 네트워크 볼륨을 연결한다. 용량은 모델을 중복 없이 넣는 조건으로 70GB 이상. CPU 오프로딩을 사용하므로 호스트 RAM도 확인한다(128GB 권장, 할당 확인 필요).
6. 아래 파일을 업로드하고 환경변수 LORA_SHA256을 설정한 다음에만 테스트 요청을 보낸다. 시작 명령은 비워두고 Dockerfile의 CMD를 사용한다.

## 볼륨에 넣을 파일

```text
/runpod-volume/
  models/qwen-edit-2511/model_index.json
  models/qwen-edit-2511/{transformer,text_encoder,vae,tokenizer,processor,scheduler}/...
  loras/checkpoint.safetensors
  references/adelia-winter.png     # 편집 테스트 시 사용자가 선택한 원본
  results/                       # 작업마다 고유 폴더에 PNG와 metadata.json 저장
```

베이스는 `Qwen/Qwen-Image-Edit-2511`, 기존 테스트 revision `6f3ccc0b56e431dc6a0c2b2039706d7d26f22cb9` 기준이다.
기존 서버의 Hugging Face snapshot을 복사한다면 심볼릭 링크를 실제 파일로 해제해서 복사해야 한다. snapshot 링크만 올리면 동작하지 않는다.
LoRA는 쓰기가 끝난 체크포인트의 복사본을 사용한다. 다운로드 전후 SHA256을 비교하고 그 값을 LORA_SHA256에 입력한다. optimizer와 학습 데이터는 필요 없다.
HF_HUB_OFFLINE=1로 실행하므로 누락 파일을 GPU 실행 중 자동 다운로드하지 않는다. 실패 시 Logs에서 단계별 경과시간을 확인한다.

RunPod의 네트워크 볼륨 S3 API를 쓰면 GPU를 켜지 않고 업로드/다운로드할 수 있다. RunPod 화면에서 표시하는 endpoint URL, region, bucket(volume ID), S3 credentials를 사용한다. S3 자격증명은 일반 RunPod API 키와 다르다. 로컬 AWS CLI profile `runpod`에 저장하고 코드나 GitHub에는 넣지 않는다.

```sh
# 아래 UPPER_CASE 값은 RunPod Storage 화면의 실제 값으로 교체한다.
aws --profile runpod --endpoint-url ENDPOINT --region REGION s3 cp ./base/ s3://VOLUME_ID/models/qwen-edit-2511/ --recursive
aws --profile runpod --endpoint-url ENDPOINT --region REGION s3 cp ./checkpoint.safetensors s3://VOLUME_ID/loras/checkpoint.safetensors
aws --profile runpod --endpoint-url ENDPOINT --region REGION s3 cp ./references/ s3://VOLUME_ID/references/ --recursive
aws --profile runpod --endpoint-url ENDPOINT --region REGION s3 cp s3://VOLUME_ID/results/ ./results/ --recursive
```

## 요청과 결과

RunPod endpoint의 요청 화면에 test-request.json을 입력하거나 `/run` API로 전송한다. 처음에는 1건만 보내 로딩 및 LoRA 호환성을 검증한다. 이 패키지는 자동 재요청을 하지 않는다.
references가 비어 있으면 1024×1024 흰 캔버스를 참조로 사용한다. 교복·포즈 테스트는 references를 `["adelia-winter.png"]`로 바꾸고 prompt에 변경 지시를 넣는다. 최대 참조 2장, 출력 1장씩 지원한다.
같은 prompt/seed에서 lora_scale=0과 1을 각각 요청하면 베이스/체크포인트를 비교할 수 있다. 결과 메타데이터에 실제 LoRA SHA256, 입력 조건, 소요 시간, GPU peak allocated 메모리를 기록한다. 이 값은 nvidia-smi 전체 사용량과 다르다.
API는 결과 파일 경로와 메타데이터를 반환한다. PNG는 위 S3 명령으로 직접 내려받는다. API 응답 크기 제한 때문에 원본 이미지를 Base64로 넣지 않는다.
실패는 RunPod job FAILED로 보고되며 코드에서 자동 재시작하거나 학습 작업을 실행하지 않는다. 플랫폼의 재시도 정책은 별도로 확인한다.

## Docker를 사용하는 경우

```sh
docker build --platform linux/amd64 -t YOUR_ACCOUNT/qwen-edit-worker:v1 .
docker push YOUR_ACCOUNT/qwen-edit-worker:v1
```

실제로 push한 주소만 Container image에 입력한다. 위 YOUR_ACCOUNT는 예제이며 배포 가능한 이미지 주소가 아니다.
GPU가 켜진 시간에는 로딩과 유휴 대기도 과금된다. 볼륨은 GPU가 없어도 별도 과금된다. 테스트 후 결과를 내려받고 불필요한 endpoint/volume은 정리한다.

공식 문서:
- https://docs.runpod.io/serverless/workers/github-integration
- https://docs.runpod.io/serverless/endpoints/endpoint-configurations
- https://docs.runpod.io/storage/network-volumes

