const markdownIt = require("markdown-it");
const markdownItAnchor = require("markdown-it-anchor");
const markdownItFootnote = require("markdown-it-footnote");
require("dotenv").config();

module.exports = function (eleventyConfig) {
  // Configure markdown-it with mermaid diagram support
  const md = markdownIt({
    html: true,
    linkify: true,
    typographer: true,
  }).use(markdownItAnchor, {
    permalink: markdownItAnchor.permalink.headerLink(),
  }).use(markdownItFootnote);

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

  // Inject SITE_URL from environment into site data (overrides site.json only if set)
  if (process.env.SITE_URL) {
    eleventyConfig.addGlobalData("site.url", process.env.SITE_URL);
  }

  // Pass through static assets
  eleventyConfig.addPassthroughCopy("src/assets");
  eleventyConfig.addPassthroughCopy({ "src/llms.txt": "llms.txt" });

  // Pass through article images (subfolders containing images)
  eleventyConfig.addPassthroughCopy("src/articles/**/*.png");
  eleventyConfig.addPassthroughCopy("src/articles/**/*.jpg");
  eleventyConfig.addPassthroughCopy("src/articles/**/*.jpeg");
  eleventyConfig.addPassthroughCopy("src/articles/**/*.gif");
  eleventyConfig.addPassthroughCopy("src/articles/**/*.svg");
  eleventyConfig.addPassthroughCopy("src/articles/**/*.webp");

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

  // Return the first N items of an array
  eleventyConfig.addFilter("head", function (array, n) {
    if (!Array.isArray(array)) return array;
    return array.slice(0, n);
  });

  // Current year filter for footer copyright
  eleventyConfig.addFilter("currentYear", function () {
    return new Date().getFullYear();
  });

  // ISO date string filter for sitemap
  eleventyConfig.addFilter("dateISOString", function (date) {
    return new Date(date).toISOString();
  });

  // Strip HTML tags (for llms-full.txt plain-text output)
  eleventyConfig.addFilter("striptags", function (str) {
    if (!str) return "";
    return str
      .replace(/<[^>]*>/g, "")
      .replace(/\n{3,}/g, "\n\n")
      .trim();
  });

  // HTML escape filter (for Atom feed)
  eleventyConfig.addFilter("escape", function (str) {
    if (!str) return "";
    return str
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
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
