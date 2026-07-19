-- Create the students table
CREATE TABLE IF NOT EXISTS students (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  email      VARCHAR(150) NOT NULL UNIQUE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Create the grades table
CREATE TABLE IF NOT EXISTS grades (
  id         SERIAL PRIMARY KEY,
  student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  subject    VARCHAR(100) NOT NULL,
  score      INTEGER NOT NULL CHECK (score >= 0 AND score <= 100),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Seed sample students
INSERT INTO students (name, email) VALUES
  ('Alice Mwangi',   'alice@kubeverse.io'),
  ('Brian Ochieng',  'brian@kubeverse.io'),
  ('Carol Njeri',    'carol@kubeverse.io'),
  ('David Kimani',   'david@kubeverse.io'),
  ('Esther Wanjiku', 'esther@kubeverse.io')
ON CONFLICT (email) DO NOTHING;

-- Seed sample grades
INSERT INTO grades (student_id, subject, score) VALUES
  (1, 'Linux Fundamentals',  88),
  (1, 'Docker Essentials',   92),
  (2, 'Linux Fundamentals',  74),
  (2, 'Docker Essentials',   81),
  (3, 'Linux Fundamentals',  95),
  (3, 'Docker Essentials',   78),
  (4, 'Linux Fundamentals',  62),
  (4, 'Docker Essentials',   70),
  (5, 'Linux Fundamentals',  85),
  (5, 'Docker Essentials',   90)
ON CONFLICT DO NOTHING;
