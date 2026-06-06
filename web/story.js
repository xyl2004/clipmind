const steps = Array.from(document.querySelectorAll(".story-step"));
const stageImage = document.querySelector("#stage-image");
const stageCount = document.querySelector("#stage-count");
const stageTitle = document.querySelector("#stage-title");
const stageCopy = document.querySelector("#stage-copy");

function setActiveStep(step) {
  const index = steps.indexOf(step);
  if (index < 0 || step.classList.contains("is-active")) return;

  steps.forEach((item) => item.classList.toggle("is-active", item === step));
  stageCount.textContent = `${String(index + 1).padStart(2, "0")} / ${String(steps.length).padStart(2, "0")}`;
  stageTitle.textContent = step.dataset.title;
  stageCopy.textContent = step.dataset.copy;

  const nextImage = step.dataset.image;
  if (stageImage.getAttribute("src") === nextImage) return;

  stageImage.classList.add("is-swapping");
  window.setTimeout(() => {
    stageImage.setAttribute("src", nextImage);
    stageImage.setAttribute("alt", step.dataset.alt);
    stageImage.classList.remove("is-swapping");
  }, 140);
}

const observer = new IntersectionObserver(
  (entries) => {
    const visible = entries
      .filter((entry) => entry.isIntersecting)
      .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];

    if (visible) setActiveStep(visible.target);
  },
  {
    root: null,
    rootMargin: "-28% 0px -28% 0px",
    threshold: [0.2, 0.45, 0.7],
  },
);

steps.forEach((step) => observer.observe(step));
