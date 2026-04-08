from ninja import NinjaAPI

from .auth import DeviceTokenAuth, DoctorJWTAuth
from .routers.auth import router as auth_router
from .routers.doctors import router as doctors_router
from .routers.patients import router as patients_router
from .routers.quizzes import router as quizzes_router

api = NinjaAPI(title='Medical Hearing Test API', version='1.0.0')

api.add_router('/auth', auth_router, tags=['auth'])
api.add_router('/patients', patients_router, auth=DeviceTokenAuth(), tags=['patients'])
api.add_router('/doctors', doctors_router, auth=DoctorJWTAuth(), tags=['doctors'])
api.add_router('/quizzes', quizzes_router, auth=DeviceTokenAuth(), tags=['quizzes'])
