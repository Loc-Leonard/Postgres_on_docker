-- Проекты
CREATE TABLE app.project (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       text NOT NULL,
  status     text NOT NULL CHECK (status IN ('planned','active','paused','done')),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Полигон объекта (границы на карте)
CREATE TABLE app.project_area (
  project_id uuid PRIMARY KEY REFERENCES app.project(id) ON DELETE CASCADE,
  geom       geometry(Polygon, 4326) NOT NULL
);
CREATE INDEX project_area_gix ON app.project_area USING GIST (geom);

-- Задачи (диаграмма Ганта)
CREATE TABLE app.task (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id    uuid NOT NULL REFERENCES app.project(id) ON DELETE CASCADE,
  name          text NOT NULL,
  start_planned date NOT NULL,
  end_planned   date NOT NULL,
  start_actual  date,
  end_actual    date,
  status        text NOT NULL DEFAULT 'planned'
                 CHECK (status IN ('planned','in_progress','done','blocked')),
  CONSTRAINT task_dates_chk CHECK (end_planned >= start_planned)
);
CREATE INDEX task_proj_status_idx ON app.task(project_id, status, start_planned);

-- Визиты (кто/где/когда)
CREATE TABLE app.visit (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id uuid NOT NULL REFERENCES app.project(id) ON DELETE CASCADE,
  actor_id   uuid NOT NULL,
  role       text NOT NULL CHECK (role IN ('foreman','control_service','inspector')),
  visited_at timestamptz NOT NULL DEFAULT now(),
  location   geometry(Point, 4326) NOT NULL
);
CREATE INDEX visit_proj_time_idx ON app.visit(project_id, visited_at);
CREATE INDEX visit_loc_gix ON app.visit USING GIST(location);

-- Замечания/нарушения
CREATE TABLE app.issue (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id   uuid NOT NULL REFERENCES app.project(id) ON DELETE CASCADE,
  created_by   uuid NOT NULL,
  role_context text NOT NULL CHECK (role_context IN ('control_service','inspector')),
  type         text NOT NULL CHECK (type IN ('remark','violation')),
  status       text NOT NULL DEFAULT 'open'
                 CHECK (status IN ('open','in_progress','fixed','accepted','rejected')),
  description  text,
  due_at       timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  location     geometry(Point, 4326)
);
CREATE INDEX issue_proj_status_due_idx ON app.issue(project_id, status, due_at);
CREATE INDEX issue_loc_gix ON app.issue USING GIST(location);
CREATE INDEX issue_desc_trgm ON app.issue USING GIN (description gin_trgm_ops);

-- Вложения (ссылки на файлы в хранилище)
CREATE TABLE app.attachment (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id  uuid NOT NULL REFERENCES app.project(id) ON DELETE CASCADE,
  owner_table text NOT NULL,
  owner_id    uuid NOT NULL,
  file_url    text NOT NULL,
  file_type   text,
  uploaded_by uuid NOT NULL,
  uploaded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX attachment_owner_idx ON app.attachment(owner_table, owner_id);
