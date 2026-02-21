---
layout: base.njk
title: Project References
description: A selection of projects where I've delivered value as a freelance Java consultant.
---

<section class="page-hero">
  <div class="container">
    <h1>📂 Project References</h1>
    <p>A curated selection of engagements showcasing my hands-on work across cloud, backend, and DevOps domains.</p>
  </div>
</section>

<section class="section">
  <div class="container">
    {% if projects.length > 0 %}
    <div class="projects-grid">
      {% for project in projects %}
      <div class="project-card">
        <div class="project-card-header">
          <h3>{{ project.title }}</h3>
          <span class="project-status status-{{ project.status }}">
            {% if project.status == "completed" %}Completed
            {% elif project.status == "ongoing" %}Ongoing
            {% else %}Confidential{% endif %}
          </span>
        </div>
        {% if project.period %}
        <div class="article-date">🗓️ {{ project.period }}</div>
        {% endif %}
        <div class="project-meta">
          {% if project.industry %}
          <span class="project-industry">🏢 {{ project.industry }}</span>
          {% endif %}
          {% if project.role %}
          <span class="project-role">👤 {{ project.role }}</span>
          {% endif %}
        </div>
        <p>{{ project.description }}</p>
        {% if project.technologies %}
        <div class="project-tech">
          {% for tech in project.technologies %}
          <span>{{ tech }}</span>
          {% endfor %}
        </div>
        {% endif %}
      </div>
      {% endfor %}
    </div>
    {% else %}
    <div class="empty-state">
      <p>🚧 Project references coming soon. See also my <a href="https://linkedin.com/in/tomseidel" target="_blank" rel="noopener">LinkedIn Profile</a>.</p>
    </div>
    {% endif %}
  </div>
</section>

<section class="availability-banner">
  <div class="container">
    <h2>Interested in working together?</h2>
    <p>Let's discuss how I can contribute to your next project.</p>
    <a href="mailto:tom.seidel@remus-software.org" class="btn-white">📫 Get in Touch</a>
  </div>
</section>
