package app.kcna26.details

/**
 * Real responses from https://sessionize.com/api/v2/uo948i5p/view/markdown/session/<id>
 * (fetched 2026-11-08, CRLF line endings kept). scripts/fetch_details.py parse() turns each
 * into exactly its details.json entry.
 */
object SessionizeSamples {
    val byId: Map<String, String> = mapOf(
        "1202489" to (
            "# Securing Rural Colorado with Open Source: Running a Student-Led SOC on Kubernetes\r\n" +
            "\r\n" +
            "KubeCon + CloudNativeCon North America 2026 \u00B7 [All sessions](https://sessionize.com/api/v2/uo948i5p/view/markdown)\r\n" +
            "\r\n" +
            "- **Session ID:** 1202489\r\n" +
            "- **When:** Tuesday, November 10, 2026 11:30 am - 12:00 pm (Mountain Standard Time, UTC-07)\r\n" +
            "- **Room:** Salt Palace | Level 1 | Grand Ballroom BDF\r\n" +
            "- **Speakers:** Maciej Wal\r\n" +
            "\r\n" +
            "## Description\r\n" +
            "\r\n" +
            "When a previous supplier dropped support for Colorado in the spring of 2024, the Cybersecurity Center at Metropolitan State University of Denver needed to build a replacement quickly.\r\n" +
            "\r\n" +
            "What started as four virtual machines scaled into a multi-cluster Kubernetes platform. Keycloak for multi-tenant identity, ArgoCD for GitOps, OPA Gatekeeper for policy, Envoy Gateway for traffic management, and cert-manager for TLS. All running in production for roughly \$1,000 a month.\r\n" +
            "\r\n" +
            "The core SOC runs on OpenSearch with Fluent Bit and Suricata, where student security analysts investigate real threats from live data. Student developers maintain the platform infrastructure itself, contributing to GitOps workflows and operations. Both groups gain hands-on experience with CNCF projects used in production worldwide.\r\n" +
            "\r\n" +
            "This talk covers architecture decisions, the VM-to-Kubernetes migration, how we built a community around students and underserved organizations, and the mistakes made along the way.\r\n" +
            "\r\n" +
            "## Speaker\r\n" +
            "\r\n" +
            "- [Maciej Wal](https://sessionize.com/api/v2/uo948i5p/view/markdown/speaker/f15aabfc-c3ad-49b1-8c73-a089f9e2a09b) \u2014 Cybersecurity Platform Architect, The Cybersecurity Center at MSU Denver\r\n"
        ),
        "1289660" to (
            "# The Future of Kubernetes Eviction and Node Lifecycle\r\n" +
            "\r\n" +
            "KubeCon + CloudNativeCon North America 2026 \u00B7 [All sessions](https://sessionize.com/api/v2/uo948i5p/view/markdown)\r\n" +
            "\r\n" +
            "- **Session ID:** 1289660\r\n" +
            "- **When:** Wednesday, November 11, 2026 5:00 pm - 5:30 pm (Mountain Standard Time, UTC-07)\r\n" +
            "- **Room:** Salt Palace | Level 2 | 251 A-C\r\n" +
            "- **Speakers:** Lucy Sweet, Ryan Hallisey, Filip K\u0159epinsk\u00FD\r\n" +
            "\r\n" +
            "## Description\r\n" +
            "\r\n" +
            "Kubernetes disruption handling is evolving from a collection of custom solutions and workarounds into a more cooperative lifecycle model. Join the Node Lifecycle Working Group for an update on two key efforts: the Eviction Request API for workload disruption coordination, and Specialized Lifecycle Management.\r\n" +
            "\r\n" +
            "We will discuss how the new declarative Eviction API gives workloads, controllers, and administrators a more explicit way to negotiate disruption than today\u2019s best-effort eviction paths. We will explore how it fits alongside PDBs, API-initiated eviction, preemption, autoscaling, and how it can help with app migration and maintenance automation.\r\n" +
            "\r\n" +
            "We will also cover Node Lifecycle Conditions, the v1alpha foundation for Specialized Lifecycle Management. This change introduces new conditions to Nodes for draining and node maintenance. A shared condition model gives Kubernetes components and ecosystem controllers a common place to observe the Node lifecycle.\r\n" +
            "\r\n" +
            "## Speakers\r\n" +
            "\r\n" +
            "- [Lucy Sweet](https://sessionize.com/api/v2/uo948i5p/view/markdown/speaker/a5321460-037e-4a00-8746-56eb0ed1c8b7) \u2014 Member of Technical Staff at Anthropic\r\n" +
            "- [Ryan Hallisey](https://sessionize.com/api/v2/uo948i5p/view/markdown/speaker/99fe91c0-7a01-4e59-8655-e15b20fd4f0f) \u2014 Nvidia, Software Engineer\r\n" +
            "- [Filip K\u0159epinsk\u00FD](https://sessionize.com/api/v2/uo948i5p/view/markdown/speaker/9f9859a4-b16d-45b2-99b3-1f525fafa93b) \u2014 Principal Software Engineer, Red Hat\r\n"
        ),
        "1289637" to (
            "# Emissary-Ingress: State of the Project\r\n" +
            "\r\n" +
            "KubeCon + CloudNativeCon North America 2026 \u00B7 [All sessions](https://sessionize.com/api/v2/uo948i5p/view/markdown)\r\n" +
            "\r\n" +
            "- **Session ID:** 1289637\r\n" +
            "- **When:** Tuesday, November 10, 2026 2:50 pm - 3:20 pm (Mountain Standard Time, UTC-07)\r\n" +
            "- **Room:** Salt Palace | Level 2 | 254\r\n" +
            "- **Speakers:** Flynn -\r\n" +
            "\r\n" +
            "## Description\r\n" +
            "\r\n" +
            "Emissary-ingress 4.1 is shipping! Emissary 4 has been a big change to the way one of the first Kubernetes-native, self-service API gateways and ingress controllers gets built and maintained, and we'd like to share what's been going on and what's coming up.\r\n" +
            "\r\n" +
            "In this session, we'll start with a quick overview of the need for ingress controllers in general, the benefits of self-service developer workflows, and how Emissary-ingress can help with these issues. We'll also cover what Emissary 4 brings to the table and how to get involved as a contributor. Emissary's maintainer sessions are always great opportunities to talk directly with Emissary-ingress maintainers and make sure your voice is heard when it comes to the project's future -- looking forward to seeing you there!\r\n" +
            "\r\n" +
            "## Speaker\r\n" +
            "\r\n" +
            "- [Flynn -](https://sessionize.com/api/v2/uo948i5p/view/markdown/speaker/c74b27cd-28e1-453b-8bc7-16857ee29370) \u2014 Technical Evangelist, Buoyant\r\n"
        ),
        "1289901" to (
            "# Kyverno: The Supercharged Future of Cloud Native Policy as Code\r\n" +
            "\r\n" +
            "KubeCon + CloudNativeCon North America 2026 \u00B7 [All sessions](https://sessionize.com/api/v2/uo948i5p/view/markdown)\r\n" +
            "\r\n" +
            "- **Session ID:** 1289901\r\n" +
            "- **When:** Monday, November 9, 2026 2:29 pm - 2:34 pm (Mountain Standard Time, UTC-07)\r\n" +
            "- **Room:** Hyatt Regency | Level 4 | Regency Ballroom B-D\r\n" +
            "- **Speakers:** Suhani \u200E\r\n" +
            "\r\n" +
            "## Description\r\n" +
            "\r\n" +
            "This session explores how Kyverno supercharges Common Expression Language (CEL) to deliver advanced resource lifecycle management for Kubernetes and beyond.\r\n" +
            "\r\n" +
            "While native Kubernetes handles basic validation checks, it stops short of what enterprise platforms require. Attendees will see how Kyverno bridges these gaps\u2014empowering platform teams with complex validations, mutative rules, dynamic resource generation, and deep context-awareness (such as image metadata lookups and external API calls). Finally, the session showcases how Kyverno is expanding its footprint beyond Kubernetes clusters, allowing organizations to write unified, high-performance policies that secure the entire cloud-native ecosystem.\r\n" +
            "\r\n" +
            "## Speaker\r\n" +
            "\r\n" +
            "- [Suhani \u200E](https://sessionize.com/api/v2/uo948i5p/view/markdown/speaker/6c45a782-eb54-4742-b4cf-08838a75d909) \u2014 Contributor @Kyverno\r\n"
        ),
        "1342434" to (
            "# Kubernetes Meet + Greet\r\n" +
            "\r\n" +
            "KubeCon + CloudNativeCon North America 2026 \u00B7 [All sessions](https://sessionize.com/api/v2/uo948i5p/view/markdown)\r\n" +
            "\r\n" +
            "- **Session ID:** 1342434\r\n" +
            "- **When:** Wednesday, November 11, 2026 12:20 pm - 2:20 pm (Mountain Standard Time, UTC-07)\r\n" +
            "- **Room:** Salt Palace | Level 2 | Upper Mezzanine\r\n" +
            "\r\n" +
            "## Description\r\n" +
            "\r\n" +
            "\\***PLEASE GRAB YOUR LUNCH FIRST, THEN EXIT THE SHOWCASE FROM THE HALL 2/3 EXIT, GO UP THE STAIRS OR ESCALATORS TOWARDS THE 2ND FLOOR UPPER MEZZANINE.***\r\n" +
            "\r\n" +
            "The Kubernetes Meet & Greet is your chance to connect directly with the teams that build and run Kubernetes.\r\n" +
            "Representatives from Kubernetes SIGs and Working Groups will be available to share what they work on, the challenges they\u2019re tackling, and how you can get involved, whether that\u2019s through code, documentation, testing, events, or community support.\r\n" +
            "\r\n" +
            "This is an informal, drop-in session designed for both new and existing contributors. If you\u2019re curious about contributing to Kubernetes, looking for a SIG that matches your interests, or hoping to expand your involvement in the community, this is the perfect place to start conversations and make connections.\r\n"
        ),
    )
}
