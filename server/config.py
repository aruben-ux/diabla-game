"""Server configuration loaded from environment variables."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Database
    database_url: str = "postgresql+asyncpg://diabla:diabla@localhost:5432/diabla"

    # JWT
    jwt_secret: str = "CHANGE-ME-IN-PRODUCTION"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440  # 24 hours

    # Server
    host: str = "0.0.0.0"
    port: int = 8080
    public_host: str = "5.78.206.166"  # Address clients connect to for game servers

    # Game server spawning
    godot_executable: str = "/usr/local/bin/godot"
    godot_project_path: str = "/opt/diabla/diabla.pck"
    game_port_start: int = 9000
    game_port_end: int = 9099
    game_server_secret: str = "CHANGE-ME-GAME-SECRET"

    model_config = {"env_prefix": "DIABLA_"}


settings = Settings()
