# Contract section 6: Lambda Python base image, linux/amd64, handler.lambda_handler.
# Build from the repo root with:  docker build --platform linux/amd64 app/
FROM public.ecr.aws/lambda/python:3.12

# Dependencies first, so code changes don't reinstall them (faster CI builds).
COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt --target ${LAMBDA_TASK_ROOT}

# The VADER lexicon ships inside the package, so the model is baked into the
# image and cold starts need no download.
COPY model.py handler.py ${LAMBDA_TASK_ROOT}/

CMD ["handler.lambda_handler"]
