package com.k8s.appa.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

@RestController
public class HealthController {

    private static final Logger logger = LoggerFactory.getLogger(HealthController.class);

    @GetMapping("/health")
    public Map<String, String> health() {
        logger.info("Health check endpoint called");
        Map<String, String> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "app-a");
        return response;
    }

    @GetMapping("/api/greet")
    public Map<String, String> greet() {
        logger.info("Greet endpoint called");
        Map<String, String> response = new HashMap<>();
        response.put("message", "Hello from App A");
        response.put("service", "app-a");
        return response;
    }
}
