# Module 6 — Service Discovery, Readiness & Recovery

**Course:** CMPE 200 · San Jose State University  
**Instructor:** Bhargavi Trivedi

---

## Overview

This project demonstrates Kubernetes service discovery, readiness probes, and Pod recovery by deploying a small inventory application on a local Kubernetes cluster. It covers three key concepts:

1. **Service Discovery** — clients always talk to a stable DNS name, never to individual Pod IPs.
2. **Readiness Probes** — unhealthy Pods are automatically removed from the load-balancer without being restarted.
3. **Self-Healing** — when a Pod is deleted, Kubernetes replaces it automatically and the Service routes traffic to the new Pod.

---

## Architecture
