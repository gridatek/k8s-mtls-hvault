package com.k8s.appb.controller;

import com.k8s.appb.service.AppAClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class CommunicationController {

    private final AppAClient appAClient;

    public CommunicationController(AppAClient appAClient) {
        this.appAClient = appAClient;
    }

    @GetMapping("/call-app-a")
    public Map<String, String> callAppA() {
        String responseFromA = appAClient.callAppA();
        Map<String, String> response = new HashMap<>();
        response.put("from", "app-b");
        response.put("app-a-response", responseFromA);
        return response;
    }
}
