const markdownIt = require("markdown-it");
const markdownItAnchor = require("markdown-it-anchor");
require("dotenv").config();

module.exports = function (eleventyConfig) {
  // Configure markdown-it with mermaid diagram support
  const md = markdownIt({
    html: true,
    linkify: true,
    typographer: true,
  }).use(markdownItAnchor, {
    permalink: markdownItAnchor.permalink.headerLink(),
  });

  // Render ```mermaid code blocks as <div class="mermaid"> for mermaid.js
  const defaultFence = md.renderer.rules.fence.bind(md.renderer.rules);
  md.renderer.rules.fence = function (tokens, idx, options, env, self) {
    const token = tokens[idx];
    if (token.info.trim() === "mermaid") {
      return `<div class="mermaid">${token.content}</div>`;
    }
    return defaultFence(tokens, idx, options, env, self);
  };

  eleventyConfig.setLibrary("md", md);

  // Inject SITE_URL from environment into site data
  eleventyConfig.addGlobalData("site.url", process.env.SITE_URL || "");

  // Pass through static assets
  eleventyConfig.addPassthroughCopy("src/assets");
  eleventyConfig.addPassthroughCopy({ "src/llms.txt": "llms.txt" });

  // Articles collection (all markdown files in articles/ except index)
  eleventyConfig.addCollection("articles", function (collectionApi) {
    return collectionApi
      .getFilteredByGlob("src/articles/*.md")
      .filter((item) => !item.fileSlug.includes("index"))
      .sort((a, b) => b.date - a.date);
  });

  // Date formatting filter
  eleventyConfig.addFilter("dateFormat", function (date) {
    return new Date(date).toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
    });
  });

  // Current year filter for footer copyright
  eleventyConfig.addFilter("currentYear", function () {
    return new Date().getFullYear();
  });

  // ISO date string filter for sitemap
  eleventyConfig.addFilter("dateISOString", function (date) {
    return new Date(date).toISOString();
  });

  return {
    dir: {
      input: "src",
      output: "dist",
      includes: "_includes",
      data: "_data",
    },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
  };
};
